@TestOn('vm')
library;

// Exercise real ingress/handlers offline, including the pre-cache Gateway filter.
import 'dart:async';
import 'dart:mirrors';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

Future<void> receive(Harness h, {int id = 42, TestTextChannel? channel}) =>
    h.invoke('_receiveMessage', [
      TestEvent(TestMessage(channel ?? h.channel, messageId: id)),
    ]);

class _Interaction implements ApplicationCommandInteraction {
  final acknowledged = Completer<void>();
  @override
  Future<void> acknowledge({bool? isEphemeral}) async {
    acknowledged.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #guildId => Snowflake(1),
        #channelId => Snowflake(10),
        #token => 'offline',
        _ => super.noSuchMethod(invocation),
      };
}

class _Context extends TestContext implements InteractionChatContext {
  @override
  final ChatCommand command;
  @override
  final ApplicationCommandInteraction interaction;
  @override
  List<dynamic> arguments = [];
  @override
  final Map<String, dynamic> rawArguments = {};
  _Context(super.channel, this.command, this.interaction);
}

class _Contexts extends ContextManager {
  final Harness h;
  final release = Completer<void>();
  final entered = Completer<void>();
  bool fail = false;
  _Contexts(super.commands, this.h);

  @override
  Future<InteractionChatContext> createInteractionChatContext(
    ApplicationCommandInteraction interaction,
    List<InteractionOption> options,
    ChatCommand command,
  ) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    if (fail) throw StateError('context resolution failed');
    return _Context(h.channel, command, interaction);
  }
}

class _Plugin extends CommandsPlugin {
  final Harness h;
  late final _Contexts _contexts = _Contexts(this, h);
  @override
  _Contexts get contextManager => _contexts;
  _Plugin(this.h)
    : super(
        prefix: null,
        options: const CommandsOptions(autoAcknowledgeInteractions: false),
      );
}

// Instantiate the same event-manager type installed by production, substituting
// only context resolution (which would otherwise fetch Discord guild/channel).
(CommandsPlugin, _Plugin, EventManager) ingress(Harness h) {
  final production =
      reflect(h.bot).invoke(h.symbol('_createCommands'), []).reflectee
          as CommandsPlugin;
  final plugin = _Plugin(h);
  final type = reflect(production.eventManager).type;
  final events =
      type.newInstance(const Symbol(''), [plugin, h.bot]).reflectee
          as EventManager;
  return (production, plugin, events);
}

Map<GameKey, Completer<void>> gates(Harness h) =>
    reflect(h.bot).getField(h.symbol('_commandGates')).reflectee
        as Map<GameKey, Completer<void>>;

class _ReplyContext extends TestContext {
  final List<String> calls;
  final bool fail;
  _ReplyContext(super.channel, this.calls, {this.fail = false});
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #respond) {
      calls.add('commandReply');
      if (fail) return Future<Message>.error(StateError('response failed'));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.bot.close());

  test(
    'queued slash command is acknowledged before its channel slot opens',
    () async {
      final (production, plugin, events) = ingress(h);
      final command = production.children.whereType<ChatCommand>().first;
      final interaction = _Interaction();
      final release = Completer<void>();
      final blocker = h.queue.run(key, () => release.future);
      plugin.contextManager.fail = true;
      final pending = events.processChatInteraction(interaction, [], command);
      final failure = expectLater(pending, throwsStateError);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(interaction.acknowledged.isCompleted, isTrue);
        expect(plugin.contextManager.entered.isCompleted, isFalse);
      } finally {
        release.complete();
        plugin.contextManager.release.complete();
        await Future.wait([blocker, failure]);
      }
      expect(gates(h), isEmpty);
    },
  );

  test('message with no prior command proceeds normally', () async {
    await h.enable();
    await receive(h);
    expect(h.games.calls, ['guess']);
    expect(h.channel.sendAttempts, hasLength(1));
    expect(gates(h), isEmpty);
  });

  test('disabled channel with no pending command stays ignored', () async {
    await receive(h);
    expect(h.games.calls, isEmpty);
    expect(h.channel.sendAttempts, isEmpty);
    expect(gates(h), isEmpty);
  });

  test('enabled start replies before its later message is processed', () async {
    await h.enable();
    final release = Completer<void>();
    h.games.startGate = release.future;
    final command = h.command(using: _ReplyContext(h.channel, h.games.calls));
    await h.games.startEntered.future;
    final gate = gates(h)[key]!;
    final message = receive(h);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(gate.isCompleted, isFalse);
      expect(h.games.guesses, isEmpty);
    } finally {
      release.complete();
      await Future.wait([command, message]);
    }
    expect(h.games.calls, [
      'guild',
      'current',
      'start',
      'commandReply',
      'guess',
    ]);
    expect(gate.isCompleted, isTrue);
    expect(gates(h), isEmpty);
  });

  test('later disable cannot overtake message waiting behind start', () async {
    final release = Completer<void>();
    h.games.startGate = release.future;
    final start = h.command();
    await h.games.startEntered.future;
    final firstGate = gates(h)[key]!;
    final first = receive(h, id: 42);
    final second = receive(h, id: 43);
    final disable = h.command(start: false, disable: true);
    final lastGate = gates(h)[key]!;
    final afterDisable = receive(h, id: 44);
    try {
      expect(identical(firstGate, lastGate), isFalse);
      expect(lastGate.isCompleted, isFalse);
    } finally {
      release.complete();
      await Future.wait([start, first, second, disable, afterDisable]);
    }
    expect(h.games.guesses.map((guess) => guess.messageId), [42, 43]);
    expect(h.games.calls, [
      'guild',
      'current',
      'start',
      'guess',
      'guess',
      'guild',
    ]);
    expect(h.channel.sendAttempts, hasLength(2));
    expect(firstGate.isCompleted, isTrue);
    expect(lastGate.isCompleted, isTrue);
    expect(gates(h), isEmpty);
  });

  test(
    'independent channel message proceeds while a command is blocked',
    () async {
      const otherKey = GameKey(guildId: 1, channelId: 20);
      h.repository.enabled = {otherKey};
      await h.channels.refresh();
      final release = Completer<void>();
      h.games.startGate = release.future;
      final start = h.command();
      await h.games.startEntered.future;
      final other = TestTextChannel(20);
      try {
        await receive(h, channel: other).timeout(const Duration(seconds: 2));
        expect(h.games.guesses.single.key, otherKey);
        expect(other.sendAttempts, hasLength(1));
        expect(gates(h)[key]!.isCompleted, isFalse);
      } finally {
        release.complete();
        await start;
      }
    },
  );

  test(
    'command repository failure completes its gate and permits next message',
    () async {
      await h.enable();
      h.games.failUpsert = true;
      final command = h.command();
      final gate = gates(h)[key]!;
      final message = receive(h);
      await Future.wait([command, message]);
      expect(h.context.replies.single.content, retryMessage);
      expect(h.games.calls, ['guild', 'guess']);
      expect(gate.isCompleted, isTrue);
      expect(gates(h), isEmpty);
    },
  );

  test('failed command and retry response still release the gate', () async {
    await h.enable();
    h.games.failUpsert = true;
    final command = h.command(
      using: _ReplyContext(h.channel, h.games.calls, fail: true),
    );
    final failure = expectLater(command, throwsStateError);
    final gate = gates(h)[key]!;
    final message = receive(h);
    await Future.wait([failure, message]);
    expect(h.games.calls, ['guild', 'commandReply', 'guess']);
    expect(gate.isCompleted, isTrue);
    expect(gates(h), isEmpty);
  });

  test(
    'message admitted before disable keeps its earlier queue slot',
    () async {
      await h.enable();
      final message = receive(h);
      final disable = h.command(start: false, disable: true);
      await Future.wait([message, disable]);
      expect(h.games.calls, ['guess', 'guild']);
      expect(h.channel.sendAttempts, hasLength(1));
      expect(h.channels.contains(key), isFalse);
    },
  );

  test(
    'failed context resolution releases pending messages and removes gate',
    () async {
      await h.enable();
      final (production, plugin, events) = ingress(h);
      final command = production.children.whereType<ChatCommand>().first;
      plugin.contextManager.fail = true;
      final pending = events.processChatInteraction(
        _Interaction(),
        [],
        command,
      );
      final failure = expectLater(pending, throwsStateError);
      await plugin.contextManager.entered.future;
      final gate = gates(h)[key]!;
      final message = receive(h);
      plugin.contextManager.release.complete();
      await Future.wait([failure, message]);
      expect(h.games.calls, ['guess']);
      expect(gate.isCompleted, isTrue);
      expect(gates(h), isEmpty);
    },
  );

  test('close drains messages waiting for an admitted command', () async {
    final release = Completer<void>();
    h.games.startGate = release.future;
    final command = h.command();
    await h.games.startEntered.future;
    final message = receive(h);
    var closed = false;
    final closing = h.bot.close().then((_) => closed = true);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
    } finally {
      release.complete();
      await Future.wait([command, message, closing]);
    }
    expect(h.games.guesses, hasLength(1));
    expect(gates(h), isEmpty);
    await h.command();
    expect(gates(h), isEmpty);
  });

  test(
    'earlier disable blocks message during asynchronous context resolution',
    () async {
      await h.enable();
      final (production, plugin, events) = ingress(h);
      final registered = production.children
          .whereType<ChatCommand>()
          .singleWhere((command) => command.name == 'kaladont-disable');
      final command = ChatCommand(
        registered.name,
        registered.description,
        registered.execute,
      );
      plugin.addCommand(command);
      final disable = events.processChatInteraction(
        _Interaction(),
        [],
        command,
      );
      await plugin.contextManager.entered.future;
      final message = receive(h);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(h.games.guesses, isEmpty);
        expect(h.channel.sendAttempts, isEmpty);
      } finally {
        plugin.contextManager.release.complete();
        await Future.wait([disable, message]);
      }
      expect(h.repository.writes, [(key, false)]);
      expect(h.games.guesses, isEmpty);
    },
  );

  test(
    'disabled-channel resume keeps a message arriving during enable',
    () async {
      h.games.current = 'telefon';
      final command = h.command();
      final message = receive(h);
      await Future.wait([command, message]);
      expect(h.games.calls, ['guild', 'current', 'guess']);
      expect(h.context.replies.single.content, endsWith('telefon'));
      expect(h.channel.sendAttempts, hasLength(1));
    },
  );
}

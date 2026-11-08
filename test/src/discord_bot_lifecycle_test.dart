// Offline close/drain/delivery regressions. Timers and subscriptions are injected;
// start()'s live Gateway connection is deliberately never executed.
import 'dart:async';

import 'package:discord_bot/src/discord_bot.dart';
import 'package:nyxx/nyxx.dart';
import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

class TestGateway implements NyxxGateway {
  int closes = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) {
      closes++;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.bot.close());

  test('close cancels timers and waits for outstanding channel work', () async {
    final refresh = Timer.periodic(const Duration(days: 1), (_) {});
    final cleanup = Timer.periodic(const Duration(days: 1), (_) {});
    addTearDown(refresh.cancel);
    addTearDown(cleanup.cancel);
    h.field('_channelRefresh', refresh);
    h.field('_receiptCleanup', cleanup);
    final entered = Completer<void>();
    final gate = Completer<void>();
    final work = h.queue.run(key, () {
      entered.complete();
      return gate.future;
    });
    await entered.future;
    var closed = false;
    final closing = h.bot.close().then((_) => closed = true);
    expect(refresh.isActive, isFalse);
    expect(cleanup.isActive, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await work;
    await closing;
    expect(closed, isTrue);
  });

  test('close is idempotent and closes client only once', () async {
    final gateway = TestGateway();
    h.field('_client', gateway);
    await h.bot.close();
    await h.bot.close();
    expect(gateway.closes, 1);
  });

  test(
    'close waits for both maintenance operations before client close',
    () async {
      final gateway = TestGateway();
      final refresh = Completer<void>();
      final cleanup = Completer<void>();
      h.field('_client', gateway);
      h.field('_channelRefreshWork', refresh.future);
      h.field('_receiptCleanupWork', cleanup.future);
      final closing = h.bot.close();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.closes, 0);
      refresh.complete();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.closes, 0);
      cleanup.complete();
      await closing;
      expect(gateway.closes, 1);
    },
  );

  test('close cancels message and ready subscriptions', () async {
    var messagesCancelled = false;
    var readyCancelled = false;
    final messages = StreamController<MessageCreateEvent>(
      onCancel: () {
        messagesCancelled = true;
      },
    );
    final ready = StreamController<ReadyEvent>(
      onCancel: () {
        readyCancelled = true;
      },
    );
    h.field('_messages', messages.stream.listen((_) {}));
    h.field('_ready', ready.stream.listen((_) {}));
    await h.bot.close();
    expect(messagesCancelled, isTrue);
    expect(readyCancelled, isTrue);
    await messages.close();
    await ready.close();
  });

  test('failed delivery never repeats committed database guess', () async {
    await h.enable();
    h.channel.failSend = true;
    await h.message();
    expect(h.games.calls, ['guess']);
    expect(h.channel.sent, hasLength(2));
    expect(h.channel.sent.first.embeds, hasLength(1));
    expect(h.channel.sent.last.content, retryMessage);
  });

  for (final status in [
    TurnStatus.invalidWord,
    TurnStatus.duplicate,
    TurnStatus.noActiveGame,
  ]) {
    test('${status.name} sends no Discord message', () async {
      await h.enable();
      h.games.result = TurnResult(status);
      await h.message();
      expect(h.games.calls, ['guess']);
      expect(h.channel.sent, isEmpty);
    });
  }

  test('queued message succeeds after prior database failure', () async {
    await h.enable();
    h.games.failGuess = true;
    final first = h.message();
    final recover = h.queue.run(key, () async => h.games.failGuess = false);
    final second = h.message(id: 43);
    await Future.wait([first, recover, second]);
    expect(h.games.guesses.map((g) => g.messageId), [42, 43]);
    expect(h.channel.sent.first.content, retryMessage);
    expect(h.channel.sent.last.embeds!.single.title, 'Točan odgovor!');
  });

  for (final entry in <(String, int?, bool, int?, bool, bool)>[
    ('bot', 1, true, null, false, true),
    ('webhook', 1, false, 3, false, true),
    ('directMessage', null, false, null, false, true),
    ('disabledChannel', 1, false, null, false, false),
    ('shuttingDown', 1, false, null, true, true),
  ]) {
    test('Gateway filter rejects ${entry.$1}', () {
      expect(
        messageIgnoreReason(
          guildId: entry.$2,
          isBot: entry.$3,
          webhookId: entry.$4,
          closing: entry.$5,
          channelEnabled: entry.$6,
        ),
        entry.$1,
      );
    });
  }

  test('initial channel load failure prevents Gateway connection', () async {
    h.repository.failRefresh = true;
    await expectLater(h.bot.start(), throwsStateError);
    expect(h.games.calls, isEmpty);
  });
}

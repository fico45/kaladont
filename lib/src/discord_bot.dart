import 'dart:async';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

import 'config.dart';
import 'logging.dart';
import 'model/game_key.dart';
import 'repository/dictionary_repository.dart';
import 'repository/game_repository.dart';
import 'services/channel_queue.dart';
import 'services/game_service.dart';
import 'services/game_channels.dart';
import 'services/receipt_retention.dart';

final class DiscordBot {
  final AppConfig config;
  final GameService game;
  final GameRepository games;
  final ChannelQueue queue;
  final GameChannels channels;
  final Map<GameKey, Completer<void>> _commandGates = {};
  Timer? _channelRefresh;
  Timer? _receiptCleanup;
  Future<void>? _channelRefreshWork;
  Future<void>? _receiptCleanupWork;
  final ReceiptRetention retention;
  NyxxGateway? _client;
  StreamSubscription<MessageCreateEvent>? _messages;
  StreamSubscription<ReadyEvent>? _ready;
  bool _closing = false;
  final _shutdown = Completer<void>();
  Future<void>? _closeWork;
  final Future<NyxxGateway> Function(GatewayClientOptions)? _connectGateway;

  /// Stop admission and interrupt startup without discarding accepted work.
  void requestShutdown() {
    if (_closing) return;
    _closing = true;
    _shutdown.complete();
    _channelRefresh?.cancel();
    _receiptCleanup?.cancel();
  }

  DiscordBot({
    required this.config,
    required this.game,
    required this.games,
    required this.queue,
    required this.channels,
    required this.retention,
    this._connectGateway,
  });

  Future<void> start() async {
    if (_closing) return;
    await Future.any([channels.refresh(), _shutdown.future]);
    if (_closing) return;
    final commands = _createCommands();
    final options = GatewayClientOptions(
      loggerName: 'KaladontBot',
      plugins: [Logging(), commands],
    );
    if (_closing) return;
    // Nyxx has no cancellation API. Keep observing the losing future so late
    // errors are handled and a late client is closed, never installed.
    final connecting =
        (_connectGateway?.call(options) ??
                Nyxx.connectGateway(
                  config.discordToken,
                  GatewayIntents.messageContent |
                      GatewayIntents.allUnprivileged,
                  options: options,
                ))
            .then((client) async {
              if (_closing) {
                await client.close();
              } else {
                _client = client;
              }
            });
    await Future.any([connecting, _shutdown.future]);
    if (_closing) {
      await close();
      return;
    }
    final client = _client!;
    _ready = client.onReady.listen((event) {
      logEvent(
        'info',
        'Discord ready',
        context: {
          'bot_id': event.user.id.toString(),
          'guild_ids': event.guilds
              .map((guild) => guild.id.toString())
              .toList(),
        },
      );
    });
    _messages = client.onMessageCreate.listen(
      (event) => unawaited(_receiveMessage(event)),
      onError: (Object error, StackTrace stack) {
        logEvent(
          'error',
          'Discord message stream failed (${error.runtimeType})',
          stackTrace: stack,
        );
      },
    );
    // Do not launch maintenance while startup can still be interrupted.
    _channelRefresh = Timer.periodic(const Duration(minutes: 5), (_) {
      _channelRefreshWork = _refreshChannels();
      unawaited(_channelRefreshWork);
    });
    _receiptCleanup = Timer.periodic(const Duration(hours: 1), (_) {
      _receiptCleanupWork = _pruneReceipts();
      unawaited(_receiptCleanupWork);
    });
    _receiptCleanupWork = _pruneReceipts();
    unawaited(_receiptCleanupWork);
  }

  CommandsPlugin _createCommands() {
    final commands =
        _OrderedCommandsPlugin(
            this,
            prefix: mentionOr((_) => '!'),
            options: CommandsOptions(
              logErrors: true,
              type: CommandType.slashOnly,
            ),
          )
          ..addCommand(
            ChatCommand(
              'kaladont-start',
              'Započni novu igru Kaladonta',
              id('kaladont-start', (ChatContext context) async {
                await _command(context, startGame: true, queued: true);
              }),
            ),
          )
          ..addCommand(
            ChatCommand(
              'kaladont-ranks',
              'Rank lista Kaladont igre',
              id('kaladont-ranks', (ChatContext context) async {
                await _command(context, startGame: false, queued: true);
              }),
            ),
          );
    commands.addCommand(
      ChatCommand(
        'kaladont-disable',
        'Onemogući Kaladont u ovom kanalu',
        id('kaladont-disable', (ChatContext context) async {
          await _command(
            context,
            startGame: false,
            disableChannel: true,
            queued: true,
          );
        }),
      ),
    );
    return commands;
  }

  Future<void> _receiveMessage(MessageCreateEvent event) async {
    final author = event.message.author;
    final context = _messageContext(event);
    final reason = messageIgnoreReason(
      guildId: event.guildId?.value,
      isBot: author is! User || author.isBot,
      webhookId: event.message.webhookId?.value,
      closing: _closing,
      channelEnabled:
          event.guildId != null &&
          _enabledOrPending(
            GameKey(
              guildId: event.guildId!.value,
              channelId: event.message.channel.id.value,
            ),
          ),
    );
    logEvent(
      'info',
      'Discord message received',
      context: {
        ...context,
        'content_length': event.message.content.length,
        'disposition': reason == null ? 'processing' : 'ignored',
        if (reason != null) 'reason': reason,
      },
    );
    if (reason != null) return;
    await _message(event);
  }

  bool _enabledOrPending(GameKey key) =>
      channels.contains(key) || _commandGates.containsKey(key);

  Future<void> _runCommand(GameKey key, Future<void> Function() action) async {
    final gate = Completer<void>();
    _commandGates[key] = gate;
    try {
      await queue.run(key, action);
    } finally {
      gate.complete();
      // An earlier command must never remove or complete a newer gate.
      if (identical(_commandGates[key], gate)) _commandGates.remove(key);
    }
  }

  Future<void> _command(
    ChatContext context, {
    required bool startGame,
    bool disableChannel = false,
    bool queued = false,
  }) async {
    if (_closing && !queued) return;
    final guild = context.guild;
    if (guild == null) {
      await context.respond(
        MessageBuilder(content: 'Kaladont se može igrati samo na serveru.'),
      );
      return;
    }
    final key = GameKey(
      guildId: guild.id.value,
      channelId: context.channel.id.value,
    );
    final contextFields = <String, Object?>{
      'guild_id': guild.id.toString(),
      'guild_name': guild.name,
      'channel_id': context.channel.id.toString(),
      'command': disableChannel
          ? 'kaladont-disable'
          : startGame
          ? 'kaladont-start'
          : 'kaladont-ranks',
    };
    logEvent('info', 'Discord command received', context: contextFields);
    Future<void> action() async {
      try {
        await games.upsertGuild(
          id: guild.id.value,
          name: guild.name,
          iconUrl: guild.icon?.url.toString(),
        );
        if (disableChannel) {
          await channels.setEnabled(key, false);
          await context.respond(
            MessageBuilder(
              embeds: [
                EmbedBuilder()
                  ..description = 'Kaladont je onemogućen u ovom kanalu.'
                  ..color = DiscordColor(0xFF0000),
              ],
            ),
          );
        } else if (startGame) {
          await channels.setEnabled(key, true);
          final reply = await game.start(key);
          await context.respond(
            MessageBuilder(
              embeds: [
                EmbedBuilder()
                  ..description = reply.message
                  ..color = DiscordColor(switch (reply.outcome) {
                    StartOutcome.created => 0x008000,
                    StartOutcome.existing ||
                    StartOutcome.concurrent => 0x90EE90,
                  }),
              ],
            ),
          );
        } else {
          final players = await games.ranking(key.guildId);
          final embed = EmbedBuilder()
            ..color = DiscordColor(0x90EE90)
            ..title = 'Rank lista Kaladont igre'
            ..description = players.isEmpty
                ? 'Još nema osvojenih bodova.'
                : null
            ..fields = players
                .map(
                  (p) => EmbedFieldBuilder(
                    name: p.username,
                    value: p.score.toString(),
                    isInline: false,
                  ),
                )
                .toList();
          await context.respond(MessageBuilder(embeds: [embed]));
        }
      } catch (error, stack) {
        logEvent(
          'error',
          'Command failed (${error.runtimeType})',
          context: contextFields,
          stackTrace: stack,
        );
        await context.respond(
          MessageBuilder(
            content: error is EmptyDictionaryException
                ? 'Rječnik nema dostupnih početnih riječi.'
                : _retryMessage,
          ),
        );
      }
    }

    // Slash callbacks already own the slot reserved before context resolution.
    // Direct handler calls reserve their own slot and gate here.
    if (queued) {
      await action();
    } else {
      await _runCommand(key, action);
    }
  }

  Future<void> _message(MessageCreateEvent event) async {
    final key = GameKey(
      guildId: event.guildId!.value,
      channelId: event.message.channel.id.value,
    );
    final context = _messageContext(event);
    final gate = _commandGates[key];
    try {
      // Reserve the message slot now, before waiting, so later commands cannot
      // overtake it. Only await the gate captured at ingress, never a newer one.
      await queue.run(key, () async {
        if (gate != null && !gate.isCompleted) await gate.future;
        if (!channels.contains(key)) return;
        try {
          final reply = await game.guess(
            Guess(
              key: key,
              messageId: event.message.id.value,
              playerId: event.message.author.id.value,
              username: event.message.author.username,
              avatarUrl: event.message.author.avatar?.url.toString() ?? '',
              word: event.message.content,
            ),
            onIgnored: (reason) => logEvent(
              reason == GuessIgnoreReason.emptyContent ? 'warning' : 'info',
              'Discord message ignored',
              context: {...context, 'reason': reason.name},
            ),
          );
          if (reply == null) return;
          final embed = EmbedBuilder()
            ..title = switch (reply.type) {
              ReplyType.correct => 'Točan odgovor!',
              ReplyType.victory => 'Igra završena!',
              ReplyType.wrongPrefix ||
              ReplyType.samePlayer ||
              ReplyType.reusedWord ||
              ReplyType.unknownWord ||
              ReplyType.disabled => 'Ups!',
            }
            ..description = reply.message
            ..color = DiscordColor(switch (reply.type) {
              ReplyType.correct => 0x98FB98,
              ReplyType.victory => 0x008000,
              ReplyType.wrongPrefix => 0xFFA500,
              ReplyType.samePlayer => 0xFFD580,
              ReplyType.reusedWord => 0x800080,
              ReplyType.unknownWord => 0xCBC3E3,
              ReplyType.disabled => 0xFF0000,
            });
          await event.message.channel.sendMessage(
            MessageBuilder(embeds: [embed]),
          );
          logEvent(
            'info',
            'Discord reply sent',
            context: {...context, 'reply_type': reply.type.name},
          );
        } catch (error, stack) {
          logEvent(
            'error',
            'Guess processing failed (${error.runtimeType})',
            context: context,
            stackTrace: stack,
          );
          await event.message.channel.sendMessage(
            MessageBuilder(content: _retryMessage),
          );
        }
      });
    } catch (error, stack) {
      logEvent(
        'error',
        'Discord response failed (${error.runtimeType})',
        context: context,
        stackTrace: stack,
      );
    }
  }

  Map<String, Object?> _messageContext(MessageCreateEvent event) => {
    'guild_id': event.guildId?.toString(),
    'guild_name': _client?.guilds.cache[event.guildId]?.name,
    'channel_id': event.message.channel.id.toString(),
    'message_id': event.message.id.toString(),
    'author_id': event.message.author.id.toString(),
  };

  Future<void> _pruneReceipts() async {
    try {
      final removed = await retention.run();
      if (removed > 0) {
        logEvent(
          'info',
          'Expired turn receipts removed',
          context: {'count': removed},
        );
      }
    } catch (error, stack) {
      logEvent(
        'error',
        'Receipt cleanup failed (${error.runtimeType})',
        stackTrace: stack,
      );
    }
  }

  Future<void> _refreshChannels() async {
    try {
      await channels.refresh();
    } catch (error, stack) {
      logEvent(
        'error',
        'Channel refresh failed (${error.runtimeType})',
        stackTrace: stack,
      );
    }
  }

  Future<void> close() {
    requestShutdown();
    return _closeWork ??= _close();
  }

  Future<void> _close() async {
    try {
      await _messages?.cancel();
      await _ready?.cancel();
      await queue.drain();
      await _channelRefreshWork;
      await _receiptCleanupWork;
    } finally {
      await _client?.close();
    }
  }
}

// Reserve a channel slot before nyxx_commands performs any asynchronous guild/
// channel lookup. A gate created only inside the command callback is too late.
final class _OrderedCommandsPlugin extends CommandsPlugin {
  final DiscordBot bot;

  _OrderedCommandsPlugin(
    this.bot, {
    required super.prefix,
    required super.options,
  });

  late final EventManager _events = _CommandEvents(this, bot);

  @override
  EventManager get eventManager => _events;
}

final class _CommandEvents extends EventManager {
  final DiscordBot bot;

  _CommandEvents(super.commands, this.bot);

  @override
  Future<void> processChatInteraction(
    ApplicationCommandInteraction interaction,
    List<InteractionOption> options,
    ChatCommand command,
  ) {
    if (bot._closing) return Future<void>.value();
    final guildId = interaction.guildId;
    final channelId = interaction.channelId;
    if (guildId == null || channelId == null) {
      return super.processChatInteraction(interaction, options, command);
    }
    // Context creation and the plugin's normal auto-ack timer now run inside
    // the queue. Defer at ingress instead, so a busy channel cannot expire the
    // interaction while it waits for its turn. This is not a gameplay reply.
    final acknowledgement = command.resolvedOptions.autoAcknowledgeInteractions!
        ? interaction.acknowledge(
            isEphemeral:
                command.resolvedOptions.defaultResponseLevel!.hideInteraction,
          )
        : Future<void>.value();
    // Observe early failures even while an earlier queue slot is still busy;
    // awaiting the original future below still propagates them to the plugin.
    acknowledgement.ignore();
    return bot._runCommand(
      GameKey(guildId: guildId.value, channelId: channelId.value),
      () async {
        await acknowledgement;
        await super.processChatInteraction(interaction, options, command);
      },
    );
  }
}

const _retryMessage =
    'Usluga trenutačno nije dostupna. Pokušajte ponovno. Ako je potez već spremljen, provjerite trenutačni niz.';

String? messageIgnoreReason({
  required int? guildId,
  required bool isBot,
  required int? webhookId,
  bool closing = false,
  bool channelEnabled = true,
}) {
  if (closing) return 'shuttingDown';
  if (guildId == null) return 'directMessage';
  if (webhookId != null) return 'webhook';
  if (isBot) return 'bot';
  if (!channelEnabled) return 'disabledChannel';
  return null;
}

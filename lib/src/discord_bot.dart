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
  Timer? _channelRefresh;
  Timer? _receiptCleanup;
  Future<void>? _channelRefreshWork;
  Future<void>? _receiptCleanupWork;
  final ReceiptRetention retention;
  NyxxGateway? _client;
  StreamSubscription<MessageCreateEvent>? _messages;
  StreamSubscription<ReadyEvent>? _ready;
  bool _closing = false;

  DiscordBot({
    required this.config,
    required this.game,
    required this.games,
    required this.queue,
    required this.channels,
    required this.retention,
  });

  Future<void> start() async {
    await channels.refresh();
    _channelRefresh = Timer.periodic(const Duration(minutes: 5), (_) {
      _channelRefreshWork = _refreshChannels();
      unawaited(_channelRefreshWork);
    });
    _receiptCleanupWork = _pruneReceipts();
    unawaited(_receiptCleanupWork);
    _receiptCleanup = Timer.periodic(const Duration(hours: 1), (_) {
      _receiptCleanupWork = _pruneReceipts();
      unawaited(_receiptCleanupWork);
    });
    final commands =
        CommandsPlugin(
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
                await _command(context, startGame: true);
              }),
            ),
          )
          ..addCommand(
            ChatCommand(
              'kaladont-ranks',
              'Rank lista Kaladont igre',
              id('kaladont-ranks', (ChatContext context) async {
                await _command(context, startGame: false);
              }),
            ),
          );
    commands.addCommand(
      ChatCommand(
        'kaladont-disable',
        'Onemogući Kaladont u ovom kanalu',
        id('kaladont-disable', (ChatContext context) async {
          await _command(context, startGame: false, disableChannel: true);
        }),
      ),
    );
    final client = await Nyxx.connectGateway(
      config.discordToken,
      GatewayIntents.messageContent | GatewayIntents.allUnprivileged,
      options: GatewayClientOptions(
        loggerName: 'KaladontBot',
        plugins: [Logging(), commands],
      ),
    );
    _client = client;
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
      (event) {
        final author = event.message.author;
        final context = _messageContext(event);
        final reason = messageIgnoreReason(
          guildId: event.guildId?.value,
          isBot: author is! User || author.isBot,
          webhookId: event.message.webhookId?.value,
          closing: _closing,
          channelEnabled:
              event.guildId != null &&
              channels.contains(
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
        unawaited(_message(event));
      },
      onError: (Object error, StackTrace stack) {
        logEvent(
          'error',
          'Discord message stream failed (${error.runtimeType})',
          stackTrace: stack,
        );
      },
    );
  }

  Future<void> _command(
    ChatContext context, {
    required bool startGame,
    bool disableChannel = false,
  }) async {
    if (_closing) return;
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
    await queue.run(key, () async {
      try {
        await games.upsertGuild(
          id: guild.id.value,
          name: guild.name,
          iconUrl: guild.icon?.url.toString(),
        );
        if (disableChannel) {
          await channels.setEnabled(key, false);
          await context.respond(
            MessageBuilder(content: 'Kaladont je onemogućen u ovom kanalu.'),
          );
        } else if (startGame) {
          await channels.setEnabled(key, true);
          await context.respond(MessageBuilder(content: await game.start(key)));
        } else {
          final players = await games.ranking(key.guildId);
          final embed = EmbedBuilder()
            ..color = DiscordColor.fromRgb(124, 252, 0)
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
    });
  }

  Future<void> _message(MessageCreateEvent event) async {
    final key = GameKey(
      guildId: event.guildId!.value,
      channelId: event.message.channel.id.value,
    );
    final context = _messageContext(event);
    try {
      await queue.run(key, () async {
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
              ReplyType.warning => 'Ups!',
              ReplyType.victory => 'Igra završena!',
            }
            ..description = reply.message
            ..color = DiscordColor.fromRgb(0, 200, 200);
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

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _channelRefresh?.cancel();
    _receiptCleanup?.cancel();
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

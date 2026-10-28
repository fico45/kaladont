import 'dart:async';
import 'dart:io';

import 'package:discord_bot/src/config.dart';
import 'package:discord_bot/src/discord_bot.dart';
import 'package:discord_bot/src/logging.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/channel_repository.dart';
import 'package:discord_bot/src/services/game_channels.dart';
import 'package:discord_bot/src/repository/retention_repository.dart';
import 'package:discord_bot/src/services/receipt_retention.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:discord_bot/src/services/channel_queue.dart';
import 'package:discord_bot/src/services/game_service.dart';
import 'package:supabase/supabase.dart';

Future<void> main() async {
  SupabaseClient? database;
  DiscordBot? bot;
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    final config = AppConfig.fromEnvironment();
    final client = SupabaseClient(
      config.supabaseUrl,
      config.supabaseApiKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    database = client;
    final games = SupabaseGameRepository(client);
    bot = DiscordBot(
      config: config,
      games: games,
      queue: ChannelQueue(),
      channels: GameChannels(SupabaseChannelRepository(client)),
      retention: ReceiptRetention(
        SupabaseRetentionRepository(client).pruneBatch,
      ),
      game: GameService(
        dictionary: SupabaseDictionaryRepository(client),
        games: games,
        isDev: config.isDev,
      ),
    );
    final stopped = Completer<void>();
    void stop(ProcessSignal _) {
      if (!stopped.isCompleted) stopped.complete();
    }

    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    await bot.start();
    await stopped.future;
  } catch (error, stack) {
    // Exception messages from network libraries can contain credentials/URLs.
    logEvent('error', 'Bot stopped (${error.runtimeType})', stackTrace: stack);
    if (database == null && error is FormatException) {
      logEvent('error', error.message);
    }
    exitCode = 1;
  } finally {
    try {
      await bot?.close();
    } finally {
      try {
        await database?.dispose();
      } finally {
        for (final signal in signals) {
          await signal.cancel();
        }
      }
    }
  }
}

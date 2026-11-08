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
  var startupComplete = false;
  var startupInterrupted = false;
  Timer? startupShutdownDeadline;
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
      bot?.requestShutdown();
      if (!startupComplete) {
        startupInterrupted = true;
        // Nyxx cannot cancel an in-flight connection. Bound startup cleanup
        // even if an underlying socket or client disposal never completes.
        startupShutdownDeadline ??= Timer(const Duration(seconds: 10), () {
          logEvent('error', 'Startup shutdown deadline exceeded');
          exit(1);
        });
      }
      if (!stopped.isCompleted) stopped.complete();
    }

    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    await bot.start();
    startupComplete = true;
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
      try {
        await bot?.close();
      } finally {
        await database?.dispose();
      }
    } catch (error, stack) {
      logEvent(
        'error',
        'Bot cleanup failed (${error.runtimeType})',
        stackTrace: stack,
      );
      exitCode = 1;
    } finally {
      for (final signal in signals) {
        await signal.cancel();
      }
      if (startupInterrupted) {
        startupShutdownDeadline?.cancel();
        // Owned-resource cleanup has finished. Do not leave the process alive
        // on sockets owned by a losing, non-cancellable startup future.
        exit(exitCode);
      }
    }
  }
}

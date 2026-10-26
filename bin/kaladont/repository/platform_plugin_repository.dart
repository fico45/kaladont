import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../main_activity.dart';
import '../model/game_key.dart';
import '../providers/game_state_provider.dart';
import 'client_repository.dart';

class PlatformPluginRepository {
  static Future<StreamSubscription> startAndListen({
    required ProviderContainer container,
  }) async {
    final client = await BotClient.bot;

    client.onReady.listen((_) => print('Ready!'));

    return client.onMessageCreate.listen((event) async {
      final guildId = event.guildId?.value;
      if (guildId == null || event.message.author.id == client.user.id) {
        return;
      }

      final key = GameKey(
        guildId: guildId,
        channelId: event.message.channel.id.value,
      );
      final sessions = container.read(gameSessionsProvider.notifier);
      if (!sessions.tryAcquire(key)) {
        return;
      }

      try {
        await kaladontMainActivity(
          event: event,
          key: key,
          providerContainer: container,
        );
      } catch (error, stackTrace) {
        print('Failed to process a word: $error\n$stackTrace');
      } finally {
        sessions.release(key);
      }
    });
  }
}

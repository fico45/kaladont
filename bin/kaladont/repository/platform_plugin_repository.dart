import 'dart:async';
import 'package:riverpod/riverpod.dart';
import '../main_activity.dart';
import '../providers/game_state_provider.dart';
import 'client_repository.dart';

class PlatformPluginRepository {
  static bool isProcessingWord = false;

  static Future<StreamSubscription> startAndListen({
    required ProviderContainer container,
  }) async {
    final client = await BotClient.bot;
    /*    ..registerPlugin(commands)
      ..connect(); */

    client.onReady.listen((e) {
      print("Ready!");
    });

    return client.onMessageCreate.listen((event) async {
      final gameState = container.read(gameStateProvider.notifier).state;

      print('Message: ${event.message.content}');
      if (gameState.isKaladontStarted &&
          gameState.gameChannelId == event.message.channel.id.toString() &&
          !isProcessingWord) {
        kaladontMainActivity(event: event, providerContainer: container);
      }
    });
  }
}

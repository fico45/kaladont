import 'dart:async';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';
import 'package:supabase/supabase.dart';

import '../../consts.dart';
import '../command_list.dart';
import '../main_activity.dart';
import '../providers/game_state_provider.dart';
import 'client_repository.dart';

class PlatformPluginRepository {
  static bool isProcessingWord = false;

  static Future<void> initBot() async {
    CommandsPlugin commands = CommandsPlugin(
      prefix: (message) => '!',
      options: CommandsOptions(logErrors: true, type: CommandType.slashOnly),
    );

    commands.addCommand(ChatCommands.kaladontStart);
    commands.addCommand(ChatCommands.kaladontHighScores);

    BotClient.bot
      ..registerPlugin(Logging()) // Default logging plugin
      ..registerPlugin(
          CliIntegration()) // Cli integration for nyxx allows stopping application via SIGTERM and SIGKILl
      ..registerPlugin(
          IgnoreExceptions()) // Plugin that handles uncaught exceptions that may occur
      ..registerPlugin(commands)
      ..connect();

    BotClient.bot.onReady.listen((e) {
      print("Ready!");
    });
  }

  static StreamSubscription<IMessageReceivedEvent> mainListener({
    required ProviderContainer container,
  }) {
    return BotClient.bot.eventsWs.onMessageReceived.listen((event) async {
      final gameState = container.read(gameStateProvider.notifier).state;
      var embedder = EmbedBuilder();
      embedder.title = "Power buhtla bot!";
      embedder.color = DiscordColor.blue;
      print('Message: ${event.message.content}');
      if (gameState.isKaladontStarted &&
          gameState.gameChannelId == event.message.channel.id.toString() &&
          !isProcessingWord) {
        kaladontMainActivity(
            embedder: embedder, event: event, providerContainer: container);
      }
    });
  }
}

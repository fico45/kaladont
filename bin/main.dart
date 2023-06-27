import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';
import 'consts.dart';
import 'kaladont/client.dart';
import 'kaladont/command_list.dart';
import 'kaladont/main_activity.dart';
import 'kaladont/providers/game_state_provider.dart';
import 'kaladont/providers/player_provider.dart';

int length = 0;
bool isProcessingWord = false;

void main() async {
  final container = ProviderContainer();
  ChatCommands(provider: container);
  Tokens.loadTokens();

  await container.read(playersProvider.notifier).loadPlayers();
  CommandsPlugin commands = CommandsPlugin(
    prefix: (message) => '!',
    options: CommandsOptions(logErrors: true, type: CommandType.slashOnly),
  );

  BotClient.bot
    ..registerPlugin(Logging()) // Default logging plugin
    ..registerPlugin(
        CliIntegration()) // Cli integration for nyxx allows stopping application via SIGTERM and SIGKILl
    ..registerPlugin(
        IgnoreExceptions()) // Plugin that handles uncaught exceptions that may occur
    ..registerPlugin(commands)
    ..connect();

  BotClient.bot.eventsWs.onMessageReceived.listen((event) async {
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

  commands.addCommand(ChatCommands.kaladontStart);
  commands.addCommand(ChatCommands.kaladontHighScores);

  BotClient.bot.onReady.listen((e) {
    print("Ready!");
  });

  //sortAndSendToDb(pbClient: client);
}

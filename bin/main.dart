import 'package:dotenv/dotenv.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';
import 'package:supabase/supabase.dart';

import 'kaladont/main_activity.dart';
import 'kaladont/model/word_model.dart';
import 'kaladont/providers/player_provider.dart';
import 'kaladont/services/get_random_word.dart';

Word savedWord = Word(
    currentWord: "laminat",
    previousWord: "lamela",
    lastGuess: true,
    victory: false,
    previousExistsInDictionary: true,
    possibleAnswers: 0);

int length = 0;
bool isProcessingWord = false;

class KaladontGameState {
  KaladontGameState(
      {required this.isKaladontStarted, this.lastPlayerId, this.gameChannelId});
  bool isKaladontStarted;
  String? lastPlayerId;
  String? gameChannelId;
}

KaladontGameState gameState = KaladontGameState(
  isKaladontStarted: false,
);
late final SupabaseClient client;
void main() async {
  // Where the state of our providers will be stored.
  // Avoid making this a global variable, for testability purposes.
  // If you are using Flutter, you do not need this.
  final container = ProviderContainer();

  var env = DotEnv(includePlatformEnvironment: true)..load();

  client = SupabaseClient(
    env['supaBaseUrl']!,
    env['supaBaseAPIKey']!,
  );
  //final userData = await client.users.authViaEmail(email, password);
  await container.read(playersProvider.notifier).loadPlayers();
  CommandsPlugin commands = CommandsPlugin(
    prefix: (message) => '!',
    options: CommandsOptions(logErrors: true, type: CommandType.slashOnly),
  );

  final bot = NyxxFactory.createNyxxWebsocket(
    env['websocketKey']!,
    GatewayIntents.messageContent | GatewayIntents.allUnprivileged,
  )
    ..registerPlugin(Logging()) // Default logging plugin
    ..registerPlugin(
        CliIntegration()) // Cli integration for nyxx allows stopping application via SIGTERM and SIGKILl
    ..registerPlugin(
        IgnoreExceptions()) // Plugin that handles uncaught exceptions that may occur
    ..registerPlugin(commands)
    ..connect();
  //await readFromFile();
  //final userData = await client.users.authViaEmail(email, password);

  bot.eventsWs.onMessageReceived.listen((event) async {
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
  ChatCommand kaladontHighScores = ChatCommand(
      'kaladont-ranks',
      'Rank lista Kaladont igre',
      id('kaladont-ranks', (IChatContext context) async {
        final provider = container.read(playersProvider);
        container.read(playersProvider.notifier).sortPlayers();
        List<EmbedFieldBuilder> fields = [];
        for (var player in provider) {
          fields.add(EmbedFieldBuilder(
              "${player.username}  ${player.score.toString()}"));
        }
        EmbedBuilder newEmbed = EmbedBuilder()
          ..color = DiscordColor.green
          ..title = "Rank lista Kaladont igre"
          ..fields.addAll(fields);
        final message = MessageBuilder.embed(newEmbed);
        context.respond(message);
      }));

  ChatCommand kaladontStart = ChatCommand(
      'kaladont-start',
      "Započni novu igru Kaladonta",
      id('kaladont-start', (IChatContext context) async {
        if (gameState.isKaladontStarted) {
          context.respond(MessageBuilder.content(
              'Ne možete započeti novu sesiju igre dok je već jedna u tijeku.'));
          return;
        }
        String randomWord = await getRandomWord();
        print(randomWord);
        savedWord = Word(
          currentWord: randomWord.toLowerCase(),
          previousWord: "",
          lastGuess: true,
          victory: false,
          previousExistsInDictionary: true,
          possibleAnswers: 0,
        );
        gameState.isKaladontStarted = true;
        gameState.gameChannelId = context.channel.id.toString();

        context.respond(MessageBuilder.content(
            'Nova igra kaladonta započeta! Početna riječ: $randomWord'));
      }));
  commands.addCommand(kaladontStart);
  commands.addCommand(kaladontHighScores);

  bot.onReady.listen((e) {
    print("Ready!");
  });

  //sortAndSendToDb(pbClient: client);
}

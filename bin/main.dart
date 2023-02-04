import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';
import 'package:supabase/supabase.dart';

import 'kaladont/main_activity.dart';
import 'kaladont/model/word_model.dart';
import 'kaladont/services/get_random_word.dart';

List<String> quotes = [];
Word savedWord = Word(
    currentWord: "laminat",
    previousWord: "lamela",
    lastGuess: true,
    victory: false,
    previousExistsInDictionary: true,
    possibleAnswers: 0);

int length = 0;

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
late final client;
void main() async {
  // Where the state of our providers will be stored.
  // Avoid making this a global variable, for testability purposes.
  // If you are using Flutter, you do not need this.
  //final container = ProviderContainer();

  var env = DotEnv(includePlatformEnvironment: true)..load();
  print(env['supaBaseUrl']!);
  client = SupabaseClient(
    env['supaBaseUrl']!,
    env['supaBaseAPIKey']!,
  );
  //final userData = await client.users.authViaEmail(email, password);

  CommandsPlugin commands = CommandsPlugin(
    prefix: (message) => '!',
    options: CommandsOptions(
        logErrors: true, defaultCommandType: CommandType.slashOnly),
  );

  final bot = NyxxFactory.createNyxxWebsocket(
    "MTAyMTg2NjM4NDgzOTQyMTk2Mw.GJfg3f.J1YW-Xuc0uqDHQ_TxRL5uG0q8vMsO8kWcpu4aM",
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
    print('Message: ' + event.message.content);
    if (gameState.isKaladontStarted &&
        gameState.gameChannelId == event.message.channel.id.toString()) {
      kaladontMainActivity(embedder: embedder, event: event);
    }
  });
  ChatCommand kaladontStart = ChatCommand.slashOnly(
      'kaladont-start',
      "Započni novu igru Kaladonta",
      id('kaladont-start', (IChatContext context) async {
        String randomWord = await getRandomWord();
        print(randomWord);
        savedWord = Word(
          currentWord: randomWord,
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

  bot.onReady.listen((e) {
    print("Ready!");
  });

  //sortAndSendToDb(pbClient: client);
}

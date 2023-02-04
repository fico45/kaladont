import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';
import 'package:supabase/supabase.dart';

import 'kaladont/main_activity.dart';
import 'kaladont/model/word_model.dart';
import 'kaladont/services/get_random_word.dart';

Future<void> addToFile(String textToAdd) async {
  await File("bin/quotes.txt").writeAsString(textToAdd, mode: FileMode.append);
}

String getLastTwoLetters({required String word, required int length}) {
  return word[length - 1] + word[length];
}

List<String> quotes = [];
Word savedWord = Word(
    currentWord: "laminat",
    previousWord: "lamela",
    lastGuess: true,
    victory: false,
    previousExistsInDictionary: true,
    possibleAnswers: 0);

int length = 0;
bool isKaladontStarted = false;
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
      logErrors: true,
    ),
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
    if (isKaladontStarted) {
      kaladontMainActivity(embedder: embedder, event: event);
    }
  });
  ChatCommand kaladontStart = ChatCommand(
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
        isKaladontStarted = true;
        context.respond(MessageBuilder.content(
            'Nova igra kaladonta započeta! Početna riječ: $randomWord'));
      }));
  commands.addCommand(kaladontStart);

  bot.onReady.listen((e) {
    print("Ready!");
  });

  //sortAndSendToDb(pbClient: client);
}

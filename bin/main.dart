import 'dart:io';
import 'dart:math';
import 'package:dotenv/dotenv.dart';
import 'package:nyxx/nyxx.dart';
import 'package:supabase/supabase.dart';

import 'kaladont/main_activity.dart';
import 'kaladont/model/word_model.dart';
import 'kaladont/services/check_word.dart';
import 'consts.dart';
import 'kaladont/services/get_random_word.dart';

Future<void> addToFile(String textToAdd) async {
  await File("bin/quotes.txt").writeAsString(textToAdd, mode: FileMode.append);
}

Future<void> readFromFile() async {
  File('bin/quotes.txt').readAsLines().then((List<String> contents) {
    quotes = [];
    for (var element in contents) {
      quotes.add(element);
    }
  });
  length = quotes.length;
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
);

int length = 0;

final client = SupabaseClient(
  'https://ulpwjboowijidolpwjoz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVscHdqYm9vd2lqaWRvbHB3am96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE2Njk1NDc5ODMsImV4cCI6MTk4NTEyMzk4M30.lG-ASDsVSDK2Sd372sBDZZSvPJba9m3tHzCxu52m19U',
);
void main() async {
  final env = DotEnv().load();

  //final userData = await client.users.authViaEmail(email, password);

  final bot = NyxxFactory.createNyxxWebsocket(
      "MTAyMTg2NjM4NDgzOTQyMTk2Mw.GJfg3f.J1YW-Xuc0uqDHQ_TxRL5uG0q8vMsO8kWcpu4aM",
      GatewayIntents.allUnprivileged)
    ..registerPlugin(Logging()) // Default logging plugin
    ..registerPlugin(
        CliIntegration()) // Cli integration for nyxx allows stopping application via SIGTERM and SIGKILl
    ..registerPlugin(
        IgnoreExceptions()) // Plugin that handles uncaught exceptions that may occur
    ..connect();
  //await readFromFile();
  //final userData = await client.users.authViaEmail(email, password);
  String randomWord = await getRandomWord();
  print(randomWord);
  bot.onReady.listen((e) {
    print("Ready!");
  });
  //sortAndSendToDb(pbClient: client);
  bot.eventsWs.onMessageReceived.listen((event) async {
    var embedder = EmbedBuilder();
    embedder.title = "Power buhtla bot!";
    embedder.color = DiscordColor.blue;
    kaladontMainActivity(embedder: embedder, event: event);
  });
}

void useQuotes({required INyxxWebsocket bot}) {
  bot.eventsWs.onMessageReceived.listen(
    (e) async {
      length = quotes.length;
      var embedder = EmbedBuilder();
      embedder.title = "Power buhtla bot!";
      embedder.color = DiscordColor.blue;

      if (e.message.content == "random") {
        print("Autor: ${e.message.author.username}");
        var rng = Random();
        int index = rng.nextInt(length);

        embedder.description = quotes[index];
        e.message.channel.sendMessage(MessageBuilder.embed(embedder));
        print("Poruka: ${embedder.description!}");
      } else if (e.message.content.contains("add ")) {
        String abc = e.message.content.toString();
        await addToFile('\n${abc.substring(4)}');
        await readFromFile();
      } else if (e.message.content.contains("index ")) {
        try {
          int idx = int.parse(e.message.content.substring(6));
          if (idx >= length) {
            throw "Error!";
          }
          embedder.description = quotes[idx];
          e.message.channel.sendMessage(MessageBuilder.embed(embedder));
        } catch (err) {
          print(err);
          e.message.channel.sendMessage(
              MessageBuilder.content("Enter index from 0 to ${length - 1}"));
        }
      }
    },
  );
}

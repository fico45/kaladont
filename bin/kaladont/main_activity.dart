import 'package:nyxx/nyxx.dart';

import '../main.dart';
import 'services/check_word.dart';

void kaladontMainActivity({
  required IMessageReceivedEvent event,
  required EmbedBuilder embedder,
}) async {
  print(event.message.content);
  if (event.message.content != '') {
    if (!event.message.content.contains(" ")) {
      savedWord = await checkWord(
          savedWord: savedWord, wordToCheck: event.message.content);
      if (!savedWord.previousExistsInDictionary) {
        if (gameState.lastPlayerId == event.message.author.id.toString()) {
          embedder.description =
              "Ne možete nastaviti vlastiti niz. Trenutna riječ: ${savedWord.currentWord}";
          await event.message.channel
              .sendMessage(MessageBuilder.embed(embedder));
          return;
        }
        embedder.description = "Riječ koju ste upisali ne postoji u rječniku!";
        embedder.color = DiscordColor.red;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      }
      if (savedWord.victory) {
        embedder.color = DiscordColor.green;
        embedder.description = "Čestitamo! Pobijedili ste!";
        gameState.isKaladontStarted = false;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      } else if (savedWord.lastGuess) {
        embedder.color = DiscordColor.turquoise;
        String possibleAnswers;
        savedWord.possibleAnswers == 1000
            ? possibleAnswers = '1000+'
            : possibleAnswers = savedWord.possibleAnswers.toString();
        gameState.lastPlayerId = event.message.author.id.toString();
        embedder.description =
            "Nova riječ: ${savedWord.currentWord}\nMogućih odgovora: $possibleAnswers";

        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      } else {
        embedder.color = DiscordColor.red;
        embedder.description =
            "Niste dobro nastivili buhtlin niz. Pokušajte ponovno. Trenutna riječ: ${savedWord.currentWord}";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      }
    }
  }
}

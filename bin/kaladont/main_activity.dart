import 'package:nyxx/nyxx.dart';

import '../main.dart';
import 'services/check_word.dart';

void kaladontMainActivity({
  required IMessageReceivedEvent event,
  required EmbedBuilder embedder,
}) async {
  if (event.message.content != '') {
    if (!event.message.content.contains(" ")) {
      savedWord = await checkWord(
          savedWord: savedWord, wordToCheck: event.message.content);
      if (!savedWord.previousExistsInDictionary) {
        embedder.description = "Riječ koju ste upisali ne postoji u rječniku!";
        embedder.color = DiscordColor.red;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      }
      if (savedWord.victory) {
        embedder.color = DiscordColor.green;
        embedder.description = "Čestitamo! Pobijedili ste!";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      } else if (savedWord.lastGuess) {
        embedder.color = DiscordColor.turquoise;
        String possibleAnswers;
        savedWord.possibleAnswers == 1000
            ? possibleAnswers = '1000+'
            : possibleAnswers = savedWord.possibleAnswers.toString();
        embedder.description =
            "Nova riječ: ${savedWord.currentWord}\nMogućih odgovora: $possibleAnswers";

        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      } else {
        embedder.color = DiscordColor.red;
        embedder.description =
            "Niste dobro nastivili buhtlin niz. Pokušajte ponovno. Trenutna riječ: ${savedWord.currentWord}";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
      }
    } else {
      embedder.description =
          "Niste pogodili riječ! Trenutna riječ: ${savedWord.currentWord}";
      await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
    }
  }
}

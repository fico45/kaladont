import 'package:nyxx/nyxx.dart';
import 'package:riverpod/riverpod.dart';

import '../consts.dart';
import '../main.dart';
import 'services/check_word.dart';
import 'services/player_service.dart';
import 'services/word_check_formatter.dart';

void kaladontMainActivity({
  required IMessageReceivedEvent event,
  required EmbedBuilder embedder,
  required ProviderContainer providerContainer,
}) async {
  print(event.message.content);
  if (event.message.content != '') {
    if (!event.message.content.contains(" ")) {
      if (event.message.content.contains("%")) {
        //sql injection prevention. Doesn't work though.
        embedder.description = "Zločestica bezobrazna!";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      bool canContinue = WordCheckFormatter.getFirstTwoLetters(
              word: event.message.content.toLowerCase()) ==
          WordCheckFormatter.getLastTwoLetters(
              word: savedWord.currentWord.toLowerCase(),
              length: savedWord.currentWord.length - 1);
      isProcessingWord = true;
      if (gameState.lastPlayerId == event.message.author.id.toString() &&
          canContinue) {
        embedder.description =
            "Ne možete nastaviti vlastiti niz.\nTrenutna riječ: ${savedWord.currentWord}";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      if (Globals.usedWords.contains(event.message.content.toLowerCase())) {
        embedder.description = "Riječ je već korištena!";
        embedder.color = DiscordColor.yellow;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      savedWord = await checkWord(
        savedWord: savedWord,
        wordToCheck: event.message.content.toLowerCase(),
      );
      if (!savedWord.previousExistsInDictionary) {
        embedder.description =
            "Riječ koju ste upisali ne postoji u rječniku!\nRiječ treba početi sa ${WordCheckFormatter.getLastTwoLetters(word: savedWord.currentWord.toLowerCase(), length: savedWord.currentWord.length - 1)}";
        embedder.color = DiscordColor.red;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      if (savedWord.victory) {
        embedder.color = DiscordColor.green;
        embedder.description = "Čestitamo! Pobijedili ste!";
        gameState.isKaladontStarted = false;
        gameState.lastPlayerId = '';
        await awardPoints(
          playerDiscordId: event.message.author.id.id,
          numberOfPoints: 3,
          playerDiscordUsername: event.message.author.username,
          playerDiscordAvatar: event.message.author.avatarURL(),
          providerContainer: providerContainer,
        );
        Globals.usedWords.clear();
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
      } else if (savedWord.lastGuess) {
        embedder.color = DiscordColor.turquoise;
        String possibleAnswers;
        savedWord.possibleAnswers == 1000
            ? possibleAnswers = '1000+'
            : possibleAnswers = savedWord.possibleAnswers.toString();
        gameState.lastPlayerId = event.message.author.id.toString();
        await awardPoints(
          playerDiscordId: event.message.author.id.id,
          numberOfPoints: 1,
          playerDiscordUsername: event.message.author.username,
          playerDiscordAvatar: event.message.author.avatarURL(),
          providerContainer: providerContainer,
        );
        Globals.usedWords.add(savedWord.currentWord);
        embedder.description =
            "Nova riječ: ${savedWord.currentWord}\nMogućih odgovora: $possibleAnswers";

        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      } else {
        embedder.color = DiscordColor.red;
        embedder.description =
            "Niste dobro nastivili buhtlin niz. Pokušajte ponovno. Trenutna riječ: ${savedWord.currentWord}";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
    }
  }
}

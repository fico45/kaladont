import 'package:nyxx/nyxx.dart';
import 'package:riverpod/riverpod.dart';

import '../consts.dart';
import '../main.dart';
import 'providers/game_state_provider.dart';
import 'providers/saved_word_provider.dart';
import 'services/check_word.dart';
import 'services/player_service.dart';
import 'services/word_check_formatter.dart';

void kaladontMainActivity({
  required IMessageReceivedEvent event,
  required EmbedBuilder embedder,
  required ProviderContainer providerContainer,
}) async {
  print(event.message.content);
  //check if the message contains any content
  if (event.message.content != '') {
    //check if it's a single word and not a sentence
    if (!event.message.content.contains(" ")) {
      final wordProvider = providerContainer.read(savedWordProvider.notifier);
      final gameState =
          providerContainer.read(gameStateProvider.notifier).state;
      if (event.message.content.contains("%")) {
        //sql injection prevention. Doesn't work though.
        embedder.description = "Zločestica bezobrazna!";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      String inputWord = event.message.content.toLowerCase();
      String newWordFirstLetters =
          WordCheckFormatter.getFirstTwoLetters(word: inputWord);
      String oldWordLastLetters = WordCheckFormatter.getLastTwoLetters(
          word: wordProvider.state.currentWord,
          length: wordProvider.state.currentWord.length - 1);
      //check if the previous and currnet work even match
      bool canContinue = newWordFirstLetters == oldWordLastLetters;
      isProcessingWord = true;
      if (gameState.lastPlayerId == event.message.author.id.toString() &&
          canContinue) {
        embedder.description =
            "Ne možete nastaviti vlastiti niz.\nTrenutna riječ: ${wordProvider.state.currentWord}";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      if (Globals.usedWords.contains(inputWord)) {
        embedder.description = "Riječ je već korištena!";
        embedder.color = DiscordColor.yellow;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      if (canContinue) {
        wordProvider.state = await checkWord(
          savedWord: wordProvider.state,
          wordToCheck: inputWord,
        );
      } else {
        wordProvider.state.setLastGuess(false);
      }
      if (!wordProvider.state.previousExistsInDictionary) {
        embedder.description =
            "Riječ koju ste upisali ne postoji u rječniku!\nRiječ treba početi sa ${WordCheckFormatter.getLastTwoLetters(word: wordProvider.state.currentWord.toLowerCase(), length: wordProvider.state.currentWord.length - 1)}";
        embedder.color = DiscordColor.red;
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
      //final response
      if (wordProvider.state.victory) {
        embedder.color = DiscordColor.green;
        embedder.description = "Čestitamo! Pobijedili ste!";
        gameState.isKaladontStarted = false;
        gameState.lastPlayerId = '';
        await PlayerService.awardPoints(
          playerDiscordId: event.message.author.id.id,
          numberOfPoints: 3,
          playerDiscordUsername: event.message.author.username,
          playerDiscordAvatar: event.message.author.avatarUrl(),
          providerContainer: providerContainer,
        );
        Globals.usedWords.clear();
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
      } else if (wordProvider.state.lastGuess) {
        embedder.color = DiscordColor.turquoise;
        String possibleAnswers;
        wordProvider.state.possibleAnswers == 1000
            ? possibleAnswers = '1000+'
            : possibleAnswers = wordProvider.state.possibleAnswers.toString();
        gameState.lastPlayerId = event.message.author.id.toString();
        await PlayerService.awardPoints(
          playerDiscordId: event.message.author.id.id,
          numberOfPoints: 1,
          playerDiscordUsername: event.message.author.username,
          playerDiscordAvatar: event.message.author.avatarUrl(),
          providerContainer: providerContainer,
        );
        Globals.usedWords.add(wordProvider.state.currentWord);
        embedder.description =
            "Nova riječ: ${wordProvider.state.currentWord}\nMogućih odgovora: $possibleAnswers";

        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      } else {
        embedder.color = DiscordColor.red;
        embedder.description =
            "Niste dobro nastivili buhtlin niz. Pokušajte ponovno. Trenutna riječ: ${wordProvider.state.currentWord}";
        await event.message.channel.sendMessage(MessageBuilder.embed(embedder));
        isProcessingWord = false;
        return;
      }
    }
  }
}

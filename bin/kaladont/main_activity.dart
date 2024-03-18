import 'package:nyxx/nyxx.dart';
import 'package:riverpod/riverpod.dart';

import '../consts.dart';
import 'controller/message_controller.dart';
import 'providers/game_state_provider.dart';
import 'providers/saved_word_provider.dart';
import 'repository/platform_plugin_repository.dart';
import 'services/check_word.dart';
import 'services/player_service.dart';
import 'services/word_check_formatter.dart';

void kaladontMainActivity({
  required MessageCreateEvent event,
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
        await MessageController.sendMessage(
          message: 'Zločestica bezobrazna!',
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.error,
        );
        PlatformPluginRepository.isProcessingWord = false;
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
      PlatformPluginRepository.isProcessingWord = true;
      if (!Tokens.isDev &&
          gameState.lastPlayerId == event.message.author.id.toString() &&
          canContinue) {
        await MessageController.sendMessage(
          message:
              "Ne možete nastaviti vlastiti niz.\nTrenutna riječ: ${wordProvider.state.currentWord}",
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.warning,
        );

        PlatformPluginRepository.isProcessingWord = false;
        return;
      }
      if (Globals.usedWords.contains(inputWord)) {
        await MessageController.sendMessage(
          message: "Riječ je već korištena!",
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.warning,
        );
        PlatformPluginRepository.isProcessingWord = false;
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
        await MessageController.sendMessage(
          message: '''Riječ koju ste upisali ne postoji u rječniku!
              Riječ treba početi sa ${WordCheckFormatter.getLastTwoLetters(word: wordProvider.state.currentWord.toLowerCase(), length: wordProvider.state.currentWord.length - 1)}''',
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.warning,
        );

        PlatformPluginRepository.isProcessingWord = false;
        return;
      }
      //final response
      if (wordProvider.state.victory) {
        gameState.isKaladontStarted = false;
        gameState.lastPlayerId = '';
        if (!Tokens.isDev) {
          await PlayerService.awardPoints(
            playerDiscordId: event.message.author.id.value,
            numberOfPoints: 3,
            playerDiscordUsername: event.message.author.username,
            playerDiscordAvatar:
                event.message.author.avatar?.url.toString() ?? '',
            providerContainer: providerContainer,
          );
        }
        Globals.usedWords.clear();

        await MessageController.sendMessage(
          message: "Čestitamo! Pobijedili ste!",
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.endGame,
        );

        PlatformPluginRepository.isProcessingWord = false;
      } else if (wordProvider.state.lastGuess) {
        String possibleAnswers;
        wordProvider.state.possibleAnswers == 1000
            ? possibleAnswers = '1000+'
            : possibleAnswers = wordProvider.state.possibleAnswers.toString();
        gameState.lastPlayerId = event.message.author.id.toString();
        if (!Tokens.isDev) {
          await PlayerService.awardPoints(
            playerDiscordId: event.message.author.id.value,
            numberOfPoints: 1,
            playerDiscordUsername: event.message.author.username,
            playerDiscordAvatar:
                event.message.author.avatar?.url.toString() ?? '',
            providerContainer: providerContainer,
          );
        }
        Globals.usedWords.add(wordProvider.state.currentWord);

        await MessageController.sendMessage(
          message:
              "Nova riječ: ${wordProvider.state.currentWord}\nMogućih odgovora: $possibleAnswers",
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.correctGuess,
        );

        PlatformPluginRepository.isProcessingWord = false;
        return;
      } else {
        await MessageController.sendMessage(
          message:
              "Niste dobro nastivili buhtlin niz. Pokušajte ponovno. Trenutna riječ: ${wordProvider.state.currentWord}",
          event: event,
          providerContainer: providerContainer,
          type: TypeOfMessage.failedGuess,
        );

        PlatformPluginRepository.isProcessingWord = false;
        return;
      }
    }
  }
}

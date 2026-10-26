import 'package:nyxx/nyxx.dart';
import 'package:riverpod/riverpod.dart';

import '../consts.dart';
import 'controller/message_controller.dart';
import 'model/game_key.dart';
import 'model/word_model.dart';
import 'providers/game_state_provider.dart';
import 'services/check_word.dart';
import 'services/player_service.dart';
import 'services/word_check_formatter.dart';

final RegExp _croatianWord = RegExp(r'^[a-zčćđšž]+$', caseSensitive: false);

Future<void> kaladontMainActivity({
  required MessageCreateEvent event,
  required GameKey key,
  required ProviderContainer providerContainer,
}) async {
  final inputWord = event.message.content.trim().toLowerCase();
  if (inputWord.isEmpty || !_croatianWord.hasMatch(inputWord)) {
    return;
  }

  final sessions = providerContainer.read(gameSessionsProvider.notifier);
  final session = sessions.sessionFor(key);
  if (session == null) {
    return;
  }

  final expectedLetters = WordCheckFormatter.getLastTwoLetters(
    word: session.currentWord,
    length: session.currentWord.length - 1,
  );
  final actualLetters = WordCheckFormatter.getFirstTwoLetters(word: inputWord);
  if (actualLetters != expectedLetters) {
    await MessageController.sendMessage(
      message:
          'Niste dobro nastavili niz. Trenutna riječ: ${session.currentWord}',
      event: event,
      type: TypeOfMessage.failedGuess,
    );
    return;
  }

  final playerId = event.message.author.id.value;
  if (!Tokens.isDev && session.lastPlayerId == playerId) {
    await MessageController.sendMessage(
      message:
          'Ne možete nastaviti vlastiti niz.\nTrenutna riječ: ${session.currentWord}',
      event: event,
      type: TypeOfMessage.warning,
    );
    return;
  }

  if (session.usedWords.contains(inputWord)) {
    await MessageController.sendMessage(
      message: 'Riječ je već korištena!',
      event: event,
      type: TypeOfMessage.warning,
    );
    return;
  }

  final result = await checkWord(
    savedWord: Word(
      currentWord: session.currentWord,
      previousWord: session.previousWord ?? '',
      lastGuess: true,
      victory: false,
      previousExistsInDictionary: true,
      possibleAnswers: 0,
    ),
    wordToCheck: inputWord,
    usedWords: session.usedWords,
  );

  if (!result.previousExistsInDictionary) {
    await MessageController.sendMessage(
      message:
          'Riječ ne postoji u rječniku! Riječ treba početi sa $expectedLetters.',
      event: event,
      type: TypeOfMessage.warning,
    );
    return;
  }

  if (!Tokens.isDev) {
    await PlayerService.awardPoints(
      guildId: key.guildId,
      playerDiscordId: playerId,
      numberOfPoints: result.victory ? 3 : 1,
      playerDiscordUsername: event.message.author.username,
      playerDiscordAvatar: event.message.author.avatar?.url.toString() ?? '',
    );
  }

  if (result.victory) {
    sessions.end(key);
    await MessageController.sendMessage(
      message: 'Čestitamo! Pobijedili ste!',
      event: event,
      type: TypeOfMessage.endGame,
    );
    return;
  }

  sessions.update(session.acceptWord(word: inputWord, playerId: playerId));
  final possibleAnswers = result.possibleAnswers >= 1000
      ? '1000+'
      : result.possibleAnswers.toString();
  await MessageController.sendMessage(
    message: 'Nova riječ: $inputWord\nMogućih odgovora: $possibleAnswers',
    event: event,
    type: TypeOfMessage.correctGuess,
  );
}

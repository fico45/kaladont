import '../model/game_key.dart';
import '../repository/dictionary_repository.dart';
import '../repository/game_repository.dart';
import 'word_rules.dart';

enum GuessIgnoreReason {
  emptyContent,
  invalidWord,
  noActiveGame,
  duplicateMessage,
  disabledChannel,
  staleMessage,
}

enum ReplyType {
  correct,
  victory,
  wrongPrefix,
  samePlayer,
  reusedWord,
  unknownWord,
  disabled,
}

final class GameReply {
  final String message;
  final ReplyType type;
  const GameReply(this.message, this.type);
}

enum StartOutcome { created, existing, concurrent }

final class StartReply {
  final String message;
  final StartOutcome outcome;
  const StartReply(this.message, this.outcome);
}

final class GameService {
  final DictionaryRepository dictionary;
  final GameRepository games;
  final bool isDev;
  const GameService({
    required this.dictionary,
    required this.games,
    this.isDev = false,
  });

  Future<StartReply> start(GameKey key) async {
    final existing = await games.currentWord(key);
    if (existing != null) {
      return StartReply(
        'U ovom kanalu već je pokrenuta igra. Trenutna riječ: $existing',
        StartOutcome.existing,
      );
    }
    final word = await dictionary.randomWord();
    if (!isPlayableWord(word)) {
      throw StateError('Dictionary returned an invalid starting word');
    }
    final started = await games.start(key, word);
    return started
        ? StartReply(
            'Nova igra kaladonta započeta! Početna riječ: $word',
            StartOutcome.created,
          )
        : const StartReply(
            'U ovom kanalu već je pokrenuta igra.',
            StartOutcome.concurrent,
          );
  }

  Future<GameReply?> guess(
    Guess guess, {
    void Function(GuessIgnoreReason reason)? onIgnored,
  }) async {
    final word = normalizeWord(guess.word);
    // Ignore ordinary chat, punctuation and short/invalid words without slicing them.
    if (!isPlayableWord(word)) {
      onIgnored?.call(
        word.isEmpty
            ? GuessIgnoreReason.emptyContent
            : GuessIgnoreReason.invalidWord,
      );
      return null;
    }
    final result = await games.guess(
      Guess(
        key: guess.key,
        messageId: guess.messageId,
        playerId: guess.playerId,
        username: guess.username,
        avatarUrl: guess.avatarUrl,
        word: word,
      ),
      isDev: isDev,
    );
    switch (result.status) {
      case TurnStatus.staleMessage:
        onIgnored?.call(GuessIgnoreReason.staleMessage);
        return null;
      case TurnStatus.channelDisabled:
        onIgnored?.call(GuessIgnoreReason.disabledChannel);
        return null;
      case TurnStatus.noActiveGame:
        onIgnored?.call(GuessIgnoreReason.noActiveGame);
        return null;
      case TurnStatus.duplicate:
        onIgnored?.call(GuessIgnoreReason.duplicateMessage);
        return null;
      case TurnStatus.invalidWord:
        onIgnored?.call(GuessIgnoreReason.invalidWord);
        return null;
      case TurnStatus.wrongPrefix:
        return GameReply(
          'Niste dobro nastavili niz. Trenutna riječ: ${result.word!}',
          ReplyType.wrongPrefix,
        );
      case TurnStatus.samePlayer:
        return GameReply(
          'Ne možete nastaviti vlastiti niz. Trenutna riječ: ${result.word!}',
          ReplyType.samePlayer,
        );
      case TurnStatus.reusedWord:
        return const GameReply('Riječ je već korištena!', ReplyType.reusedWord);
      case TurnStatus.unknownWord:
        return GameReply(
          'Riječ ne postoji u rječniku! Riječ treba početi sa ${result.expected!}.',
          ReplyType.unknownWord,
        );
      case TurnStatus.disabled:
        return const GameReply(
          'Kaladont je onemogućen na ovom serveru.',
          ReplyType.disabled,
        );
      case TurnStatus.victory:
        return const GameReply('Čestitamo! Pobijedili ste!', ReplyType.victory);
      case TurnStatus.applied:
        return GameReply(
          'Nova riječ: ${result.word!}\nMogućih odgovora: ${result.answers!}',
          ReplyType.correct,
        );
    }
  }
}

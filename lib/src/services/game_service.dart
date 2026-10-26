import '../model/game_key.dart';
import '../repository/dictionary_repository.dart';
import '../repository/game_repository.dart';
import 'word_rules.dart';

enum ReplyType { correct, warning, victory }

final class GameReply {
  final String message;
  final ReplyType type;
  const GameReply(this.message, [this.type = ReplyType.warning]);
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

  Future<String> start(GameKey key) async {
    final existing = await games.session(key);
    if (existing != null) {
      return 'U ovom kanalu već je pokrenuta igra. Trenutna riječ: ${existing.currentWord}';
    }
    final word = await dictionary.randomWord();
    if (!isPlayableWord(word)) {
      throw StateError('Dictionary returned an invalid starting word');
    }
    final started = await games.start(key, word);
    return started
        ? 'Nova igra kaladonta započeta! Početna riječ: $word'
        : 'U ovom kanalu već je pokrenuta igra.';
  }

  Future<GameReply?> guess(Guess guess) async {
    final word = normalizeWord(guess.word);
    // Ignore ordinary chat, punctuation and short/invalid words without slicing them.
    if (!isPlayableWord(word)) return null;
    final session = await games.session(guess.key);
    if (session == null) return null;
    final expected = lastTwoLetters(session.currentWord);
    if (firstTwoLetters(word) != expected) {
      return GameReply(
        'Niste dobro nastavili niz. Trenutna riječ: ${session.currentWord}',
      );
    }
    if (!isDev && session.lastPlayerId == guess.playerId) {
      return GameReply(
        'Ne možete nastaviti vlastiti niz. Trenutna riječ: ${session.currentWord}',
      );
    }
    if (session.usedWords.contains(word)) {
      return const GameReply('Riječ je već korištena!');
    }
    if (!await dictionary.contains(word)) {
      return GameReply(
        'Riječ ne postoji u rječniku! Riječ treba početi sa $expected.',
      );
    }
    final answers = await dictionary.countContinuations(lastTwoLetters(word), {
      ...session.usedWords,
      word,
    });
    final result = await games.commit(
      session,
      Guess(
        key: guess.key,
        messageId: guess.messageId,
        playerId: guess.playerId,
        username: guess.username,
        avatarUrl: guess.avatarUrl,
        word: word,
      ),
      victory: answers == 0,
      isDev: isDev,
    );
    if (result == CommitResult.duplicate) return null;
    if (result == CommitResult.conflict) {
      return const GameReply(
        'Igra je u međuvremenu promijenjena. Pokušajte ponovno.',
      );
    }
    if (answers == 0) {
      return const GameReply('Čestitamo! Pobijedili ste!', ReplyType.victory);
    }
    return GameReply(
      'Nova riječ: $word\nMogućih odgovora: $answers',
      ReplyType.correct,
    );
  }
}

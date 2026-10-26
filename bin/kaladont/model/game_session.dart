import 'game_key.dart';

class GameSession {
  final GameKey key;
  final String currentWord;
  final String? previousWord;
  final int? lastPlayerId;
  final Set<String> usedWords;

  const GameSession({
    required this.key,
    required this.currentWord,
    this.previousWord,
    this.lastPlayerId,
    required this.usedWords,
  });

  GameSession acceptWord({
    required String word,
    required int playerId,
  }) {
    return GameSession(
      key: key,
      currentWord: word,
      previousWord: currentWord,
      lastPlayerId: playerId,
      usedWords: {...usedWords, word},
    );
  }
}

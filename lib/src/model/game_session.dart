import 'game_key.dart';

final class GameSession {
  final GameKey key;
  final String gameId;
  final int revision;
  final String currentWord;
  final String? previousWord;
  final int? lastPlayerId;
  final Set<String> usedWords;

  GameSession({
    required this.key,
    required this.gameId,
    required this.currentWord,
    this.revision = 0,
    this.previousWord,
    this.lastPlayerId,
    required Set<String> usedWords,
  }) : usedWords = Set.unmodifiable(usedWords);

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
    key: GameKey(
      guildId: json['guild_id'] as int,
      channelId: json['channel_id'] as int,
    ),
    gameId: json['game_id'] as String,
    revision: json['revision'] as int,
    currentWord: json['current_word'] as String,
    previousWord: json['previous_word'] as String?,
    lastPlayerId: json['last_player_id'] as int?,
    usedWords: (json['used_words'] as List<dynamic>).cast<String>().toSet(),
  );
}

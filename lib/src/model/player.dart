final class Player {
  final int id;
  final String username;
  final int score;
  final String avatarUrl;

  const Player({
    required this.id,
    required this.username,
    required this.score,
    required this.avatarUrl,
  });

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    id: json['discord_user_id'] as int,
    username: json['username'] as String,
    score: json['score'] as int,
    avatarUrl: json['avatar_url'] as String? ?? '',
  );
}

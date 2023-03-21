class Player {
  int id;
  String username;
  int score;
  String playerAvatar;
  Player({
    required this.id,
    required this.username,
    required this.score,
    required this.playerAvatar,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['discord_id'],
      username: json['player_username'],
      score: json['score'],
      playerAvatar: json['player_avatar'],
    );
  }
}

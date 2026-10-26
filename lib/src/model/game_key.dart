class GameKey {
  final int guildId;
  final int channelId;

  const GameKey({required this.guildId, required this.channelId});

  @override
  bool operator ==(Object other) =>
      other is GameKey &&
      other.guildId == guildId &&
      other.channelId == channelId;

  @override
  int get hashCode => Object.hash(guildId, channelId);
}

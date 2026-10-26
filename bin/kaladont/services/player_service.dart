import '../model/player_model.dart';
import '../repository/client_repository.dart';

class PlayerService {
  static Future<void> awardPoints({
    required int guildId,
    required int playerDiscordId,
    required int numberOfPoints,
    required String playerDiscordUsername,
    required String playerDiscordAvatar,
  }) async {
    await SPC.client.rpc('award_kaladont_points', params: {
      'p_guild_id': guildId,
      'p_discord_user_id': playerDiscordId,
      'p_points': numberOfPoints,
      'p_username': playerDiscordUsername,
      'p_avatar_url': playerDiscordAvatar,
    });
  }

  static Future<List<Player>> getGuildRanking(int guildId) async {
    final response = await SPC.client
        .from('guild_player_rankings')
        .select()
        .eq('guild_id', guildId)
        .order('score', ascending: false)
        .limit(25);

    return response.map<Player>((json) => Player.fromJson(json)).toList();
  }
}

import 'package:supabase/supabase.dart';

import '../model/game_key.dart';
import '../model/game_session.dart';
import '../model/player.dart';

final class Guess {
  final GameKey key;
  final int messageId;
  final int playerId;
  final String username;
  final String avatarUrl;
  final String word;
  const Guess({
    required this.key,
    required this.messageId,
    required this.playerId,
    required this.username,
    required this.word,
    this.avatarUrl = '',
  });
}

enum CommitResult { applied, duplicate, conflict }

abstract interface class GameRepository {
  Future<GameSession?> session(GameKey key);
  Future<bool> start(GameKey key, String word);
  Future<CommitResult> commit(
    GameSession session,
    Guess guess, {
    required bool victory,
    required bool isDev,
  });
  Future<void> upsertGuild({
    required int id,
    required String name,
    String? iconUrl,
  });
  Future<List<Player>> ranking(int guildId);
}

final class SupabaseGameRepository implements GameRepository {
  final SupabaseClient client;
  const SupabaseGameRepository(this.client);

  @override
  Future<GameSession?> session(GameKey key) async {
    final row = await client
        .from('kaladont_sessions')
        .select()
        .eq('guild_id', key.guildId)
        .eq('channel_id', key.channelId)
        .eq('active', true)
        .maybeSingle();
    return row == null ? null : GameSession.fromJson(row);
  }

  @override
  Future<bool> start(GameKey key, String word) async => await client.rpc<bool>(
    'kaladont_start_game',
    params: {
      'p_guild_id': key.guildId,
      'p_channel_id': key.channelId,
      'p_word': word,
    },
  );

  @override
  Future<CommitResult> commit(
    GameSession session,
    Guess guess, {
    required bool victory,
    required bool isDev,
  }) async {
    final result = await client.rpc<String>(
      'kaladont_commit_turn',
      params: {
        'p_guild_id': guess.key.guildId,
        'p_channel_id': guess.key.channelId,
        'p_game_id': session.gameId,
        'p_revision': session.revision,
        'p_message_id': guess.messageId,
        'p_player_id': guess.playerId,
        'p_word': guess.word,
        'p_username': guess.username,
        'p_avatar_url': guess.avatarUrl,
        'p_victory': victory,
        'p_is_dev': isDev,
      },
    );
    return CommitResult.values.byName(result);
  }

  @override
  Future<void> upsertGuild({
    required int id,
    required String name,
    String? iconUrl,
  }) async {
    await client.from('discord_guilds').upsert({
      'guild_id': id,
      'name': name,
      'icon_url': iconUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Player>> ranking(int guildId) async {
    final rows = await client
        .from('guild_player_rankings')
        .select()
        .eq('guild_id', guildId)
        .order('score', ascending: false)
        .order('discord_user_id', ascending: true)
        .limit(25);
    return rows.map(Player.fromJson).toList();
  }
}

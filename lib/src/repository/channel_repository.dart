import 'package:supabase/supabase.dart';

import '../model/game_key.dart';

abstract interface class ChannelRepository {
  Future<Set<GameKey>> enabledChannels();
  Future<void> setEnabled(GameKey key, bool enabled);
}

final class SupabaseChannelRepository implements ChannelRepository {
  final SupabaseClient client;
  const SupabaseChannelRepository(this.client);

  @override
  Future<Set<GameKey>> enabledChannels() async {
    const pageSize = 500;
    final channels = <GameKey>{};
    for (var offset = 0; ; offset += pageSize) {
      final rows = await client
          .from('kaladont_channels')
          .select('guild_id,channel_id')
          .eq('enabled', true)
          .order('guild_id')
          .order('channel_id')
          .range(offset, offset + pageSize - 1);
      channels.addAll(
        rows.map(
          (row) => GameKey(
            guildId: row['guild_id'] as int,
            channelId: row['channel_id'] as int,
          ),
        ),
      );
      if (rows.length < pageSize) return channels;
    }
  }

  @override
  Future<void> setEnabled(GameKey key, bool enabled) async {
    await client.rpc<void>(
      'kaladont_set_channel_enabled',
      params: {
        'p_guild_id': key.guildId,
        'p_channel_id': key.channelId,
        'p_enabled': enabled,
      },
    );
  }
}

import 'package:riverpod/riverpod.dart';

import '../client.dart';

class ServerService {
  static Future<bool> insertDiscordServerId({
    required int serverId,
    required ProviderContainer providerContainer,
  }) async {
    try {
      final insertResponse = await SPC.client.from('discord_servers').insert({
        'server_id': serverId,
      });
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }
}

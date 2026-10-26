import 'package:nyxx/nyxx.dart';

import '../repository/client_repository.dart';

class ServerService {
  static Future<void> upsertGuild(Guild guild) async {
    await SPC.client.from('discord_guilds').upsert({
      'guild_id': guild.id.value,
      'name': guild.name,
      'icon_url': guild.icon?.url.toString(),
      'enabled': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

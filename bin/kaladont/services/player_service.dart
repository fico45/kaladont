import 'package:supabase/supabase.dart';

import '../../main.dart';

Future<bool> awardPoints({
  required int playerDiscordId,
  required int numberOfPoints,
  required String playerDiscordUsername,
  required String playerDiscordAvatar,
}) async {
  try {
    final insertResponse = await client.from('players').insert({
      'discord_id': playerDiscordId,
      'score': numberOfPoints,
      'player_username': playerDiscordUsername,
      'player_avatar': playerDiscordAvatar,
    });

    return true;
  } on PostgrestException catch (e) {
    print(e);
    final updateResponse = await client
        .from('players')
        .update({'score': numberOfPoints}).eq('discord_id', playerDiscordId);
    print(updateResponse);
    return true;
  }
}

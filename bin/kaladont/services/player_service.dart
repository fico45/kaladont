import 'package:riverpod/riverpod.dart';

import '../../main.dart';
import '../model/player_model.dart';
import '../providers/player_provider.dart';

class PlayerService {
  static Future<bool> awardPoints({
    required int playerDiscordId,
    required int numberOfPoints,
    required String playerDiscordUsername,
    required String playerDiscordAvatar,
    required ProviderContainer providerContainer,
  }) async {
    try {
      final discordPlayerInDb = providerContainer
          .read(playersProvider)
          .firstWhere((element) => element.id == playerDiscordId,
              orElse: () =>
                  Player(id: 0, username: '', score: 0, playerAvatar: ''));
      if (discordPlayerInDb.id == 0) {
        final insertResponse = await client.from('players').insert({
          'discord_id': playerDiscordId,
          'score': numberOfPoints,
          'player_username': playerDiscordUsername,
          'player_avatar': playerDiscordAvatar,
        });
        providerContainer.read(playersProvider.notifier).addPlayer(Player(
            id: playerDiscordId,
            username: playerDiscordUsername,
            score: numberOfPoints,
            playerAvatar: playerDiscordAvatar));
      } else {
        final updateResponse = await client
            .from('players')
            .update({'score': numberOfPoints + discordPlayerInDb.score}).eq(
                'discord_id', playerDiscordId);
      }
      discordPlayerInDb.score += numberOfPoints;

      return true;
    } catch (e) {
      print(e);

      return false;
    }
  }
}

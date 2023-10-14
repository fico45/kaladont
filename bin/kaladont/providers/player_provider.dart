import 'package:riverpod/riverpod.dart';

import '../repository/client_repository.dart';
import '../model/player_model.dart';

final playersProvider =
    StateNotifierProvider<PlayersProvider, List<Player>>((ref) {
  return PlayersProvider();
});

class PlayersProvider extends StateNotifier<List<Player>> {
  PlayersProvider() : super([]);

  void addPlayer(Player player) {
    final newState = [...state, player];

    state = newState;
  }

  void sortPlayers() {
    state.sort((a, b) => b.score.compareTo(a.score));
  }

  Future<void> loadPlayers() async {
    try {
      final getPlayersResponse = await SPC.client.from('players').select();
      List<Player> newPlayers = [];
      for (var element in getPlayersResponse) {
        newPlayers.add(Player(
            id: element['discord_id'],
            username: element['player_username'],
            score: element['score'],
            playerAvatar: element['player_avatar']));
      }

      for (var element in newPlayers) {
        print(element.username);
      }

      state = newPlayers;
    } catch (e) {
      print(e);
    }
  }
}

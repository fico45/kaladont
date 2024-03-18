import 'package:riverpod/riverpod.dart';

import '../repository/client_repository.dart';
import '../model/server_model.dart';

final serversProvider =
    StateNotifierProvider<ServersProvider, List<DiscordServer>>((ref) {
  return ServersProvider();
});

class ServersProvider extends StateNotifier<List<DiscordServer>> {
  ServersProvider() : super([]);

  void addServer(DiscordServer server) {
    final newState = [...state, server];

    state = newState;
  }

  Future<void> loadServers() async {
    try {
      final getServersResponse = await SPC.client.from('servers').select();
      List<DiscordServer> newServers = [];
      for (var server in getServersResponse) {
        newServers.add(DiscordServer.fromJson(server));
      }

      state = newServers;
    } catch (e) {
      print(e);
    }
  }
}

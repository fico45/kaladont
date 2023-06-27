import 'package:riverpod/riverpod.dart';

import '../client.dart';
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
      final getServersResponse =
          await SPC.client.from('discord_servers').select();
      List<DiscordServer> newServers = [];
      for (var element in getServersResponse) {
        newServers.add(DiscordServer.fromJson(getServersResponse[0]));
      }

      state = newServers;
    } catch (e) {
      print(e);
    }
  }
}

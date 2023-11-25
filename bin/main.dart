import 'package:riverpod/riverpod.dart';
import 'consts.dart';
import 'kaladont/command_list.dart';
import 'kaladont/providers/player_provider.dart';
import 'kaladont/repository/platform_plugin_repository.dart';

void main() async {
  final container = ProviderContainer();
  ChatCommands(provider: container);
  Tokens.loadTokens();

  await container.read(playersProvider.notifier).loadPlayers();

  await PlatformPluginRepository.startAndListen(
    container: container,
  );

  //sortAndSendToDb(pbClient: client);
}

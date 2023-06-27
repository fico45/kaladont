import 'package:riverpod/riverpod.dart';

import '../model/game_state_model.dart';

final gameStateProvider =
    StateNotifierProvider<KaladontGameStateProvider, KaladontGameState>((ref) {
  return KaladontGameStateProvider();
});

class KaladontGameStateProvider extends StateNotifier<KaladontGameState> {
  KaladontGameStateProvider()
      : super(KaladontGameState(
          isKaladontStarted: false,
        ));
}

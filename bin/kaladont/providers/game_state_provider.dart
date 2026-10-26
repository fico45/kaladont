import 'package:riverpod/riverpod.dart';

import '../model/game_key.dart';
import '../model/game_session.dart';

final gameSessionsProvider =
    StateNotifierProvider<GameSessionsProvider, Map<GameKey, GameSession>>(
        (ref) => GameSessionsProvider());

class GameSessionsProvider extends StateNotifier<Map<GameKey, GameSession>> {
  GameSessionsProvider() : super(const {});

  final Set<GameKey> _processing = {};

  GameSession? sessionFor(GameKey key) => state[key];

  bool start(GameSession session) {
    if (state.containsKey(session.key)) {
      return false;
    }
    state = {...state, session.key: session};
    return true;
  }

  void update(GameSession session) {
    if (!state.containsKey(session.key)) {
      return;
    }
    state = {...state, session.key: session};
  }

  void end(GameKey key) {
    state = Map<GameKey, GameSession>.of(state)..remove(key);
    _processing.remove(key);
  }

  bool tryAcquire(GameKey key) {
    if (!state.containsKey(key) || _processing.contains(key)) {
      return false;
    }
    _processing.add(key);
    return true;
  }

  void release(GameKey key) => _processing.remove(key);
}

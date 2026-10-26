import '../model/game_key.dart';
import '../repository/channel_repository.dart';

final class GameChannels {
  final ChannelRepository repository;
  Set<GameKey> _enabled = {};
  int _generation = 0;
  Future<void>? _refreshing;

  GameChannels(this.repository);

  bool contains(GameKey key) => _enabled.contains(key);

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    final generation = _generation;
    final channels = await repository.enabledChannels();
    // A command that completed during the request must win over the old snapshot.
    if (generation == _generation) _enabled = Set.of(channels);
  }

  Future<void> setEnabled(GameKey key, bool enabled) async {
    await repository.setEnabled(key, enabled);
    _generation++;
    if (enabled) {
      _enabled.add(key);
    } else {
      _enabled.remove(key);
    }
  }
}

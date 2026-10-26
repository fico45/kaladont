import '../model/game_key.dart';

// Independent channels run concurrently. Failures never poison the next task.
final class ChannelQueue {
  final Map<GameKey, Future<void>> _tails = {};

  Future<T> run<T>(GameKey key, Future<T> Function() action) async {
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _tails[key] = tail;
    try {
      return await result;
    } finally {
      if (identical(_tails[key], tail)) {
        final removed = _tails.remove(key);
        assert(identical(removed, tail));
      }
    }
  }

  Future<void> drain() => Future.wait(_tails.values.toList());
}

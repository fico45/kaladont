import 'dart:async';

import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/services/channel_queue.dart';
import 'package:test/test.dart';

void main() {
  const a = GameKey(guildId: 1, channelId: 10);
  const b = GameKey(guildId: 1, channelId: 11);
  const c = GameKey(guildId: 2, channelId: 10);
  test(
    'same-channel tasks wait in order while other channels/guilds proceed',
    () async {
      final queue = ChannelQueue();
      final gate = Completer<void>();
      final events = <int>[];
      final first = queue.run(a, () async {
        events.add(1);
        await gate.future;
        events.add(2);
      });
      final second = queue.run(a, () async {
        events.add(3);
      });
      await queue.run(b, () async {
        events.add(4);
      });
      await queue.run(c, () async {
        events.add(5);
      });
      expect(events, [1, 4, 5]);
      gate.complete();
      await Future.wait([first, second]);
      expect(events, [1, 4, 5, 2, 3]);
      await queue.drain();
    },
  );
  test('a failed task releases channel for queued tasks', () async {
    final queue = ChannelQueue();
    final failed = queue.run<void>(a, () async {
      throw StateError('unavailable');
    });
    final expectation = expectLater(failed, throwsStateError);
    final next = queue.run(a, () async => 42);
    await expectation;
    expect(await next, 42);
    await queue.drain();
  });
}

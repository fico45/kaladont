import 'dart:async';

import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/repository/channel_repository.dart';
import 'package:discord_bot/src/services/game_channels.dart';
import 'package:test/test.dart';

const first = GameKey(guildId: 1, channelId: 10);
const second = GameKey(guildId: 2, channelId: 10);

final class TestChannels implements ChannelRepository {
  Set<GameKey> stored = {first};
  Completer<Set<GameKey>>? pending;
  bool fail = false;
  @override
  Future<Set<GameKey>> enabledChannels() async {
    if (fail) throw StateError('Offline');
    return pending?.future ?? Set.of(stored);
  }

  @override
  Future<void> setEnabled(GameKey key, bool enabled) async {
    if (fail) throw StateError('Offline');
    if (enabled) {
      stored.add(key);
    } else {
      stored.remove(key);
    }
  }
}

void main() {
  test('startup restores channels and lookups are isolated by guild', () async {
    final repository = TestChannels();
    final channels = GameChannels(repository);
    expect(channels.contains(first), isFalse);
    await channels.refresh();
    expect(channels.contains(first), isTrue);
    expect(channels.contains(second), isFalse);
    await channels.setEnabled(second, true);
    await channels.setEnabled(first, false);
    final restarted = GameChannels(repository);
    await restarted.refresh();
    expect(restarted.contains(first), isFalse);
    expect(restarted.contains(second), isTrue);
  });
  test('a slow refresh cannot undo a command', () async {
    final repository = TestChannels();
    final channels = GameChannels(repository);
    await channels.refresh();
    repository.pending = Completer<Set<GameKey>>();
    final refreshing = channels.refresh();
    await channels.setEnabled(first, false);
    repository.pending!.complete({first});
    await refreshing;
    expect(channels.contains(first), isFalse);
  });
  test('failed writes and refreshes preserve the last known cache', () async {
    final repository = TestChannels();
    final channels = GameChannels(repository);
    await channels.refresh();
    repository.fail = true;
    await expectLater(channels.setEnabled(first, false), throwsStateError);
    await expectLater(channels.refresh(), throwsStateError);
    expect(channels.contains(first), isTrue);
    repository.fail = false;
    await channels.refresh();
    expect(channels.contains(first), isTrue);
  });
}

@TestOn('vm')
library;

// Real command orchestration with recording repositories and Discord doubles.
import 'dart:async';

import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.bot.close());

  test('start enables channel and starts game with dictionary word', () async {
    await h.command();
    expect(h.repository.writes, [(key, true)]);
    expect(h.channels.contains(key), isTrue);
    expect(h.games.starts, [(key, 'telefon')]);
    expect(h.games.calls, ['guild', 'current', 'start']);
    expect(
      h.context.replies.single.content,
      'Nova igra kaladonta započeta! Početna riječ: telefon',
    );
  });

  test('start resumes existing game and re-enables its channel', () async {
    // The implementation enables even an existing game (unlike brief case 2).
    h.games.current = 'telefon';
    await h.command();
    expect(
      h.context.replies.single.content,
      'U ovom kanalu već je pokrenuta igra. Trenutna riječ: telefon',
    );
    expect(h.games.starts, isEmpty);
    expect(h.dictionary.calls, 0);
    expect(h.repository.writes, [(key, true)]);
  });

  test('empty dictionary produces the command-specific response', () async {
    h.dictionary.word = null;
    await h.command();
    expect(
      h.context.replies.single.content,
      'Rječnik nema dostupnih početnih riječi.',
    );
    expect(h.games.starts, isEmpty);
  });

  test('start repository failure produces retry response once', () async {
    h.games.failStart = true;
    await h.command();
    expect(h.context.replies.single.content, retryMessage);
    expect(h.games.starts, hasLength(1));
  });

  test('disable only changes configuration, not session', () async {
    h.games.current = 'telefon';
    await h.enable();
    await h.command(start: false, disable: true);
    expect(h.repository.writes, [(key, false)]);
    expect(h.channels.contains(key), isFalse);
    expect(h.games.calls, ['guild']);
    expect(h.games.current, 'telefon');
    expect(
      h.context.replies.single.content,
      'Kaladont je onemogućen u ovom kanalu.',
    );
  });

  test('disable ahead of queued message prevents repository guess', () async {
    await h.enable();
    final gate = Completer<void>();
    final blocker = h.queue.run(key, () => gate.future);
    final disable = h.command(start: false, disable: true);
    final message = h.message();
    gate.complete();
    await Future.wait([blocker, disable, message]);
    expect(h.games.guesses, isEmpty);
    expect(h.channel.sendAttempts, isEmpty);
  });

  test('ranking reads guild without enabling channel', () async {
    await h.command(start: false);
    expect(h.repository.writes, isEmpty);
    expect(h.channels.contains(key), isFalse);
    expect(h.games.ranks, [1]);
    expect(h.games.starts, isEmpty);
  });

  test('ranking embeds preserve player ordering and score fields', () async {
    h.games.players = [
      const Player(id: 2, username: 'Ana', score: 9, avatarUrl: ''),
      const Player(id: 3, username: 'Ivo', score: 4, avatarUrl: ''),
    ];
    await h.command(start: false);
    final embed = h.context.replies.single.embeds!.single;
    expect(embed.title, 'Rank lista Kaladont igre');
    expect(embed.description, isNull);
    expect(embed.fields!.map((f) => (f.name, f.value, f.isInline)), [
      ('Ana', '9', false),
      ('Ivo', '4', false),
    ]);
  });

  test('empty ranking has Croatian empty-state description', () async {
    await h.command(start: false);
    final embed = h.context.replies.single.embeds!.single;
    expect(embed.description, 'Još nema osvojenih bodova.');
    expect(embed.fields, isEmpty);
  });

  test('command after close has no repository or response effects', () async {
    await h.bot.close();
    await h.command();
    expect(h.games.calls, isEmpty);
    expect(h.repository.writes, isEmpty);
    expect(h.context.replies, isEmpty);
  });

  test('DM command responds before touching repositories', () async {
    final context = TestContext(h.channel, guildId: null);
    await h.command(using: context);
    expect(
      context.replies.single.content,
      'Kaladont se može igrati samo na serveru.',
    );
    expect(h.games.calls, isEmpty);
    expect(h.repository.writes, isEmpty);
  });

  test(
    'start, message, and disable in the same channel preserve queue order',
    () async {
      final gate = Completer<void>();
      h.games.startGate = gate.future;
      final start = h.command();
      await h.games.startEntered.future;
      final message = h.message();
      final disable = h.command(start: false, disable: true);
      expect(h.games.guesses, isEmpty);
      expect(h.repository.writes, [(key, true)]);
      gate.complete();
      await Future.wait([start, message, disable]);
      expect(h.games.calls, ['guild', 'current', 'start', 'guess', 'guild']);
      expect(h.channel.sendAttempts, hasLength(1));
      expect(h.repository.writes, [(key, true), (key, false)]);
    },
  );

  test(
    'other channel command completes while first start is blocked',
    () async {
      final gate = Completer<void>();
      h.games.startGate = gate.future;
      final start = h.command();
      await h.games.startEntered.future;
      final other = TestContext(TestTextChannel(20));
      try {
        await h
            .command(start: false, using: other)
            .timeout(const Duration(seconds: 2));
        expect(other.replies, hasLength(1));
        expect(h.context.replies, isEmpty);
      } finally {
        gate.complete();
        await start;
      }
    },
  );

  test('channel enable failure prevents starting or reading game', () async {
    h.repository.fail = true;
    await h.command();
    expect(h.context.replies.single.content, retryMessage);
    expect(h.games.calls, ['guild']);
    expect(h.channels.contains(key), isFalse);
  });

  test('guild registration failure prevents channel mutation', () async {
    h.games.failUpsert = true;
    await h.command();
    expect(h.games.guilds, [(1, 'Test guild', null)]);
    expect(h.repository.writes, isEmpty);
    expect(h.context.replies.single.content, retryMessage);
  });
}

// Orchestration invariants at the repository boundary, NOT SQL state proofs.
// Database outcomes are scripted; UUID, score and transactional reset invariants
// require the separate SQL regression suite, not a state machine in a mock.
import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.enable();
  });
  tearDown(() => h.bot.close());

  for (final status in [
    TurnStatus.wrongPrefix,
    TurnStatus.samePlayer,
    TurnStatus.reusedWord,
  ]) {
    test('${status.name} never triggers a compensating state write', () async {
      h.games.result = TurnResult(status, word: 'telefon');
      await h.message();
      expect(h.games.calls, ['guess']);
      expect(h.games.starts, isEmpty);
      expect(h.repository.writes, isEmpty);
      expect(h.channel.sent.single.embeds!.single.title, 'Ups!');
    });
  }

  test(
    'post-victory fresh message respects authoritative no-active-game',
    () async {
      h.games.result = const TurnResult(TurnStatus.victory);
      await h.message();
      h.games.result = const TurnResult(TurnStatus.noActiveGame);
      await h.message(id: 43);
      expect(h.games.guesses.map((g) => g.messageId), [42, 43]);
      expect(h.games.calls, ['guess', 'guess']);
      expect(h.channel.sent, hasLength(1));
      expect(h.channel.sent.single.embeds!.single.title, 'Igra završena!');
      expect(h.games.starts, isEmpty);
    },
  );

  test('restart after victory requests fresh start from repository', () async {
    h.games.result = const TurnResult(TurnStatus.victory);
    await h.message();
    h.games.current = null;
    await h.command();
    expect(h.games.calls, ['guess', 'guild', 'current', 'start']);
    expect(h.games.starts, [(key, 'telefon')]);
    expect(h.context.replies.single.content, contains('Nova igra'));
    h.games.result = const TurnResult(
      TurnStatus.applied,
      word: 'oniks',
      answers: 1,
    );
    await h.message(id: 43);
    expect(h.channel.sent.last.embeds!.single.title, 'Točan odgovor!');
  });

  test(
    'development message forwards mode without separate score write',
    () async {
      final dev = Harness(isDev: true);
      addTearDown(dev.bot.close);
      await dev.enable();
      await dev.message();
      expect(dev.games.calls, ['guess']);
      expect(dev.games.development, [true]);
      expect(dev.channel.sent.single.embeds!.single.title, 'Točan odgovor!');
    },
  );

  test('development mode submits consecutive same-player messages', () async {
    final dev = Harness(isDev: true);
    addTearDown(dev.bot.close);
    await dev.enable();
    await dev.message();
    await dev.message(id: 43, text: 'kson');
    expect(dev.games.guesses.map((g) => (g.messageId, g.playerId)), [
      (42, 2),
      (43, 2),
    ]);
    expect(dev.games.development, [true, true]);
    expect(dev.games.calls, ['guess', 'guess']);
    expect(dev.channel.sent, hasLength(2));
  });
}

@TestOn('vm')
library;

// Assert actual MessageBuilder payloads emitted by DiscordBot._message;
// no copied embed-building implementation is used in this suite.
import 'package:nyxx/nyxx.dart';
import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.enable();
  });
  tearDown(() => h.bot.close());

  const outcomes = {
    TurnStatus.applied: 'Točan odgovor!',
    TurnStatus.reusedWord: 'Ups!',
    TurnStatus.victory: 'Igra završena!',
  };
  for (final entry in outcomes.entries) {
    test('${entry.key.name} reply uses current turquoise color', () async {
      h.games.result = TurnResult(entry.key, word: 'oniks', answers: 7);
      await h.message();
      expect(
        h.channel.sendAttempts.single.embeds!.single.color,
        DiscordColor.fromRgb(0, 200, 200),
      );
    });
    test('${entry.key.name} reply has exact Croatian title', () async {
      h.games.result = TurnResult(entry.key, word: 'oniks', answers: 7);
      await h.message();
      expect(h.channel.sendAttempts.single.embeds!.single.title, entry.value);
    });
  }

  test('victory description congratulates the winner', () async {
    h.games.result = const TurnResult(TurnStatus.victory);
    await h.message();
    expect(
      h.channel.sendAttempts.single.embeds!.single.description,
      'Čestitamo! Pobijedili ste!',
    );
  });

  test(
    'correct description contains authoritative word and answer count',
    () async {
      h.games.result = const TurnResult(
        TurnStatus.applied,
        word: 'oniks',
        answers: 7,
      );
      await h.message();
      expect(
        h.channel.sendAttempts.single.embeds!.single.description,
        'Nova riječ: oniks\nMogućih odgovora: 7',
      );
    },
  );

  test('ignored malformed message sends no embed or text fallback', () async {
    await h.message(text: 'hello world!');
    expect(h.channel.sendAttempts, isEmpty);
    expect(h.games.guesses, isEmpty);
  });
}

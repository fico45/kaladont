@TestOn('vm')
library;

// Assert actual payloads emitted by the real Discord handlers, offline.
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
    TurnStatus.applied: (
      0x98FB98,
      'Točan odgovor!',
      'Nova riječ: oniks\nMogućih odgovora: 7',
    ),
    TurnStatus.victory: (
      0x008000,
      'Igra završena!',
      'Čestitamo! Pobijedili ste!',
    ),
    TurnStatus.wrongPrefix: (
      0xFFA500,
      'Ups!',
      'Niste dobro nastavili niz. Trenutna riječ: oniks',
    ),
    TurnStatus.samePlayer: (
      0xFFD580,
      'Ups!',
      'Ne možete nastaviti vlastiti niz. Trenutna riječ: oniks',
    ),
    TurnStatus.reusedWord: (0x800080, 'Ups!', 'Riječ je već korištena!'),
    TurnStatus.unknownWord: (
      0xCBC3E3,
      'Ups!',
      'Riječ ne postoji u rječniku! Riječ treba početi sa on.',
    ),
    TurnStatus.disabled: (
      0xFF0000,
      'Ups!',
      'Kaladont je onemogućen na ovom serveru.',
    ),
  };
  for (final entry in outcomes.entries) {
    test(
      '${entry.key.name} emits exact color, title and description',
      () async {
        h.games.result = TurnResult(
          entry.key,
          word: 'oniks',
          answers: 7,
          expected: 'on',
        );
        await h.message();
        final message = h.channel.sendAttempts.single;
        final embed = message.embeds!.single;
        expect(embed.color, DiscordColor(entry.value.$1));
        expect(embed.title, entry.value.$2);
        expect(embed.description, entry.value.$3);
        expect(message.content, isNull);
      },
    );
  }

  for (final status in [
    TurnStatus.noActiveGame,
    TurnStatus.duplicate,
    TurnStatus.invalidWord,
    TurnStatus.channelDisabled,
    TurnStatus.staleMessage,
  ]) {
    test('${status.name} remains silent', () async {
      h.games.result = TurnResult(status);
      await h.message();
      expect(h.channel.sendAttempts, isEmpty);
    });
  }

  for (final outcome in ['created', 'existing', 'concurrent']) {
    test('start.$outcome emits a titleless colored description', () async {
      h.games.current = outcome == 'existing' ? 'telefon' : null;
      h.games.started = outcome != 'concurrent';
      await h.command();
      final message = h.context.replies.single;
      expect(message.content, isNull);
      final embed = message.embeds!.single;
      expect(
        embed.color,
        DiscordColor(outcome == 'created' ? 0x008000 : 0x90EE90),
      );
      expect(embed.title, isNull);
      expect(embed.description, switch (outcome) {
        'created' => 'Nova igra kaladonta započeta! Početna riječ: telefon',
        'existing' =>
          'U ovom kanalu već je pokrenuta igra. Trenutna riječ: telefon',
        _ => 'U ovom kanalu već je pokrenuta igra.',
      });
    });
  }

  test('disable.success emits a titleless red description', () async {
    await h.command(start: false, disable: true);
    final message = h.context.replies.single;
    expect(message.content, isNull);
    final embed = message.embeds!.single;
    expect(embed.color, DiscordColor(0xFF0000));
    expect(embed.title, isNull);
    expect(embed.description, 'Kaladont je onemogućen u ovom kanalu.');
  });

  for (final populated in [false, true]) {
    test(
      'ranks populated=$populated emits light green with existing content',
      () async {
        h.games.players = populated
            ? [const Player(id: 2, username: 'Ana', score: 9, avatarUrl: '')]
            : [];
        await h.command(start: false);
        final message = h.context.replies.single;
        expect(message.content, isNull);
        final embed = message.embeds!.single;
        expect(embed.color, DiscordColor(0x90EE90));
        expect(embed.title, 'Rank lista Kaladont igre');
        expect(
          embed.description,
          populated ? null : 'Još nema osvojenih bodova.',
        );
        expect(
          embed.fields!.map((f) => (f.name, f.value, f.isInline)),
          populated ? [('Ana', '9', false)] : isEmpty,
        );
      },
    );
  }

  for (final command in ['start', 'disable', 'ranks']) {
    test('$command command.failure remains plain text', () async {
      h.games.failUpsert = true;
      await h.command(start: command == 'start', disable: command == 'disable');
      final message = h.context.replies.single;
      expect(message.content, retryMessage);
      expect(message.embeds, isNull);
    });
    test('$command command.guildOnly remains plain text', () async {
      final context = TestContext(h.channel, guildId: null);
      await h.command(
        start: command == 'start',
        disable: command == 'disable',
        using: context,
      );
      final message = context.replies.single;
      expect(message.content, 'Kaladont se može igrati samo na serveru.');
      expect(message.embeds, isNull);
    });
  }

  test('command.emptyDictionary remains plain text', () async {
    h.dictionary.word = null;
    await h.command();
    final message = h.context.replies.single;
    expect(message.content, 'Rječnik nema dostupnih početnih riječi.');
    expect(message.embeds, isNull);
  });

  test('ignored malformed message sends no embed or text fallback', () async {
    await h.message(text: 'hello world!');
    expect(h.channel.sendAttempts, isEmpty);
    expect(h.games.guesses, isEmpty);
  });

  test('guess failure remains plain text', () async {
    h.games.failGuess = true;
    await h.message();
    final message = h.channel.sendAttempts.single;
    expect(message.content, retryMessage);
    expect(message.embeds, isNull);
  });
}

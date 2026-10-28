import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/model/player.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:discord_bot/src/services/game_service.dart';
import 'package:test/test.dart';

const key = GameKey(guildId: 1, channelId: 10);
const guess = Guess(
  key: key,
  messageId: 42,
  playerId: 2,
  username: 'Player',
  word: ' Oniks ',
);

final class TestDictionary implements DictionaryRepository {
  String? word = 'telefon';
  @override
  Future<String> randomWord() async {
    if (word == null) throw const EmptyDictionaryException();
    return word!;
  }
}

final class TestGames implements GameRepository {
  String? current = 'telefon';
  TurnResult result = const TurnResult(
    TurnStatus.applied,
    word: 'oniks',
    answers: 1,
  );
  bool fail = false;
  Guess? received;
  bool? dev;
  int calls = 0;
  @override
  Future<String?> currentWord(GameKey key) async => current;
  @override
  Future<bool> start(GameKey key, String word) async {
    current = word;
    return true;
  }

  @override
  Future<TurnResult> guess(Guess guess, {required bool isDev}) async {
    calls++;
    if (fail) throw StateError('Database unavailable');
    received = guess;
    dev = isDev;
    return result;
  }

  @override
  Future<void> upsertGuild({
    required int id,
    required String name,
    String? iconUrl,
  }) async {}
  @override
  Future<List<Player>> ranking(int guildId) async => [];
}

void main() {
  late TestDictionary dictionary;
  late TestGames games;
  late GameService service;
  setUp(() {
    dictionary = TestDictionary();
    games = TestGames();
    service = GameService(dictionary: dictionary, games: games);
  });
  test('existing game is preserved', () async {
    expect(await service.start(key), contains('već'));
    expect(games.current, 'telefon');
  });
  test('empty dictionary terminates without starting a game', () async {
    games.current = null;
    dictionary.word = null;
    await expectLater(
      service.start(key),
      throwsA(isA<EmptyDictionaryException>()),
    );
    expect(games.current, isNull);
  });
  test('guess is normalized and submitted once', () async {
    final reply = await service.guess(guess);
    expect(reply!.type, ReplyType.correct);
    expect(reply.message, contains('oniks'));
    expect(games.received!.word, 'oniks');
    expect(games.calls, 1);
    expect(games.dev, isFalse);
  });
  test('database failure propagates', () async {
    games.fail = true;
    await expectLater(service.guess(guess), throwsStateError);
  });
  test('development mode is forwarded to authoritative transaction', () async {
    await GameService(
      dictionary: dictionary,
      games: games,
      isDev: true,
    ).guess(guess);
    expect(games.dev, isTrue);
  });
  test('invalid and empty messages never reach database', () async {
    for (final word in ['a', 'hello world', '  ', 'dž']) {
      final reasons = <GuessIgnoreReason>[];
      expect(
        await service.guess(
          Guess(key: key, messageId: 3, playerId: 2, username: 'P', word: word),
          onIgnored: reasons.add,
        ),
        isNull,
      );
      expect(
        reasons.single,
        word.trim().isEmpty
            ? GuessIgnoreReason.emptyContent
            : GuessIgnoreReason.invalidWord,
      );
    }
    expect(games.calls, 0);
  });
  for (final entry in {
    TurnStatus.noActiveGame: GuessIgnoreReason.noActiveGame,
    TurnStatus.duplicate: GuessIgnoreReason.duplicateMessage,
    TurnStatus.invalidWord: GuessIgnoreReason.invalidWord,
    TurnStatus.channelDisabled: GuessIgnoreReason.disabledChannel,
    TurnStatus.staleMessage: GuessIgnoreReason.staleMessage,
  }.entries) {
    test('${entry.key.name} produces no Discord reply', () async {
      games.result = TurnResult(entry.key);
      final reasons = <GuessIgnoreReason>[];
      expect(await service.guess(guess, onIgnored: reasons.add), isNull);
      expect(reasons, [entry.value]);
    });
  }
  for (final entry in {
    TurnStatus.wrongPrefix: 'nastavili',
    TurnStatus.samePlayer: 'vlastiti',
    TurnStatus.reusedWord: 'korištena',
    TurnStatus.unknownWord: 'ne postoji',
    TurnStatus.disabled: 'onemogućen',
  }.entries) {
    test('${entry.key.name} maps authoritative failure to warning', () async {
      games.result = TurnResult(entry.key, word: 'telefon', expected: 'on');
      final reply = await service.guess(guess);
      expect(reply!.type, ReplyType.warning);
      expect(reply.message, contains(entry.value));
    });
  }
  test('victory comes from the database result', () async {
    games.result = const TurnResult(
      TurnStatus.victory,
      word: 'onja',
      answers: 0,
    );
    expect((await service.guess(guess))!.type, ReplyType.victory);
  });
}

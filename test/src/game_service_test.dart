import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/model/game_session.dart';
import 'package:discord_bot/src/model/player.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:discord_bot/src/services/game_service.dart';
import 'package:test/test.dart';

const key = GameKey(guildId: 1, channelId: 10);

final class TestDictionary implements DictionaryRepository {
  bool available = true;
  bool valid = true;
  int answers = 1;
  String? random = 'telefon';
  Set<String>? excluded;
  @override
  Future<String> randomWord() async {
    if (random == null) throw const EmptyDictionaryException();
    return random!;
  }

  @override
  Future<bool> contains(String word) async {
    if (!available) throw StateError('Database unavailable');
    return valid;
  }

  @override
  Future<int> countContinuations(String prefix, Set<String> usedWords) async {
    excluded = usedWords;
    return answers;
  }
}

final class TestGames implements GameRepository {
  GameSession? current;
  int commits = 0;
  bool? victory;
  bool? dev;
  CommitResult result = CommitResult.applied;
  @override
  Future<GameSession?> session(GameKey key) async => current;
  @override
  Future<bool> start(GameKey key, String word) async {
    if (current != null) return false;
    current = GameSession(
      key: key,
      gameId: 'test',
      currentWord: word,
      usedWords: {word},
    );
    return true;
  }

  @override
  Future<CommitResult> commit(
    GameSession session,
    Guess guess, {
    required bool victory,
    required bool isDev,
  }) async {
    commits++;
    this.victory = victory;
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
  const guess = Guess(
    key: key,
    messageId: 42,
    playerId: 2,
    username: 'Player',
    word: 'Oniks',
  );
  setUp(() {
    dictionary = TestDictionary();
    games = TestGames()
      ..current = GameSession(
        key: key,
        gameId: 'test',
        currentWord: 'telefon',
        usedWords: {'telefon'},
      );
    service = GameService(dictionary: dictionary, games: games);
  });
  test('defensively copies used words and exposes an unmodifiable set', () {
    final words = {'telefon'};
    final session = GameSession(
      key: key,
      gameId: 'test',
      currentWord: 'telefon',
      usedWords: words,
    );
    words.add('oniks');
    expect(session.usedWords, {'telefon'});
    expect(() => session.usedWords.add('oniks'), throwsUnsupportedError);
  });
  test('empty dictionary fails once without a retry loop', () async {
    games.current = null;
    dictionary.random = null;
    await expectLater(
      service.start(key),
      throwsA(isA<EmptyDictionaryException>()),
    );
    expect(games.current, isNull);
  });
  test('existing sessions cannot be overwritten', () async {
    expect(await service.start(key), contains('već'));
    expect(games.current!.currentWord, 'telefon');
  });
  test('database outage propagates instead of marking word invalid', () async {
    dictionary.available = false;
    await expectLater(service.guess(guess), throwsStateError);
    expect(games.commits, 0);
  });
  test('missing dictionary word never commits', () async {
    dictionary.valid = false;
    expect((await service.guess(guess))!.message, contains('ne postoji'));
    expect(games.commits, 0);
  });
  test('normalizes accepted word and excludes current guess from continuation count', () async {
    final reply = await service.guess(guess);
    expect(reply!.type, ReplyType.correct);
    expect(reply.message, contains('oniks'));
    expect(dictionary.excluded, {'telefon', 'oniks'});
    expect(games.commits, 1);
    expect(games.victory, isFalse);
  });
  test('only zero remaining continuations wins', () async {
    dictionary.answers = 0;
    expect((await service.guess(guess))!.type, ReplyType.victory);
    expect(games.victory, isTrue);
  });
  test('short input is ignored safely', () async {
    expect(
      await service.guess(
        const Guess(
          key: key,
          messageId: 3,
          playerId: 2,
          username: 'Player',
          word: 'a',
        ),
      ),
      isNull,
    );
    expect(games.commits, 0);
  });
  test('two-letter word can be evaluated safely', () async {
    expect(
      (await service.guess(
        const Guess(
          key: key,
          messageId: 3,
          playerId: 2,
          username: 'Player',
          word: 'on',
        ),
      ))!.type,
      ReplyType.correct,
    );
  });
  test(
    'duplicate committed message produces no second success response',
    () async {
      games.result = CommitResult.duplicate;
      expect(await service.guess(guess), isNull);
    },
  );
  test('stale session produces retry response', () async {
    games.result = CommitResult.conflict;
    expect((await service.guess(guess))!.message, contains('promijenjena'));
  });
  test('same player cannot continue outside development mode', () async {
    games.current = GameSession(
      key: key,
      gameId: 'test',
      currentWord: 'telefon',
      usedWords: {'telefon'},
      lastPlayerId: 2,
    );
    expect((await service.guess(guess))!.message, contains('vlastiti'));
    expect(games.commits, 0);
    final dev = GameService(dictionary: dictionary, games: games, isDev: true);
    expect((await dev.guess(guess))!.type, ReplyType.correct);
    expect(games.dev, isTrue);
  });
}

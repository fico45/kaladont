// Service-boundary tests: SQL regressions prove starter viability. These fakes
// only script repository outcomes; they do not reimplement dictionary filtering.
import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/model/player.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:discord_bot/src/services/game_service.dart';
import 'package:test/test.dart';

const _key = GameKey(guildId: 1, channelId: 24);

final class _Dictionary implements DictionaryRepository {
  String? selected;
  int calls = 0;

  @override
  Future<String> randomWord() async {
    calls++;
    // The real adapter converts a null random-word RPC result to this exception.
    final word = selected;
    if (word == null) throw const EmptyDictionaryException();
    return word;
  }
}

final class _Games implements GameRepository {
  String? current;
  bool started = true;
  final starts = <(GameKey, String)>[];

  @override
  Future<String?> currentWord(GameKey key) async => current;

  @override
  Future<bool> start(GameKey key, String word) async {
    starts.add((key, word));
    return started;
  }

  @override
  Future<TurnResult> guess(Guess guess, {required bool isDev}) =>
      throw UnsupportedError('Start must not submit a guess');

  @override
  Future<List<Player>> ranking(int guildId) =>
      throw UnsupportedError('Start must not read rankings');

  @override
  Future<void> upsertGuild({
    required int id,
    required String name,
    String? iconUrl,
  }) =>
      throw UnsupportedError('GameService.start must not write guild metadata');
}

void main() {
  late _Dictionary dictionary;
  late _Games games;
  late GameService service;

  setUp(() {
    dictionary = _Dictionary();
    games = _Games();
    service = GameService(dictionary: dictionary, games: games);
  });

  test(
    'empty viable pool fails once without creating a stranded game',
    () async {
      await expectLater(
        service.start(_key),
        throwsA(isA<EmptyDictionaryException>()),
      );
      expect(dictionary.calls, 1);
      expect(games.starts, isEmpty);
    },
  );

  test('existing game is preserved even when viable pool is empty', () async {
    games.current = 'telefon';
    final reply = await service.start(_key);
    expect(reply, contains('već'));
    expect(reply, contains('telefon'));
    expect(dictionary.calls, 0);
    expect(games.starts, isEmpty);
  });

  for (final word in ['bedž', 'bolj', 'konj']) {
    test(
      'selected digraph starter $word is forwarded unchanged once',
      () async {
        dictionary.selected = word;
        final reply = await service.start(_key);
        expect(reply, contains('Nova igra'));
        expect(reply, contains(word));
        expect(dictionary.calls, 1);
        expect(games.starts, [(_key, word)]);
      },
    );
  }

  test(
    'concurrent start rejection does not retry or announce a new game',
    () async {
      dictionary.selected = 'konj';
      games.started = false;
      final reply = await service.start(_key);
      expect(reply, contains('već'));
      expect(reply, isNot(contains('Nova igra')));
      expect(dictionary.calls, 1);
      expect(games.starts, [(_key, 'konj')]);
    },
  );

  test(
    'one Croatian letter cannot start a game despite two characters',
    () async {
      dictionary.selected = 'dž';
      await expectLater(service.start(_key), throwsStateError);
      expect(dictionary.calls, 1);
      expect(games.starts, isEmpty);
    },
  );

  test('later start can succeed after an empty pool is replenished', () async {
    await expectLater(
      service.start(_key),
      throwsA(isA<EmptyDictionaryException>()),
    );
    expect(games.starts, isEmpty);
    dictionary.selected = 'konj';
    expect(await service.start(_key), contains('Nova igra'));
    expect(dictionary.calls, 2);
    expect(games.starts, [(_key, 'konj')]);
  });
}

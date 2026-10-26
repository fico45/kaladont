import 'dart:convert';
import 'dart:io';

import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/model/game_session.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  late SupabaseClient client;
  late SupabaseDictionaryRepository dictionary;
  late SupabaseGameRepository games;
  late List<({String method, Uri uri, String body})> requests;
  Object? randomWord = 'telefon';
  bool fail = false;
  String commitResult = 'applied';
  final sessionJson = <String, Object?>{
    'guild_id': 7,
    'channel_id': 8,
    'game_id': '00000000-0000-0000-0000-000000000001',
    'revision': 2,
    'current_word': 'telefon',
    'previous_word': null,
    'last_player_id': null,
    'used_words': ['telefon'],
  };

  setUp(() async {
    requests = [];
    randomWord = 'telefon';
    fail = false;
    commitResult = 'applied';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((method: request.method, uri: request.uri, body: body));
      request.response.headers.contentType = ContentType.json;
      Object? response;
      if (fail) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        response = {'message': 'Unavailable', 'code': '503'};
      } else if (request.uri.path.endsWith('/rpc/kaladont_random_word')) {
        response = randomWord;
      } else if (request.uri.path.endsWith(
        '/rpc/kaladont_count_continuations',
      )) {
        response = 1005;
      } else if (request.uri.path.endsWith('/rpc/kaladont_start_game')) {
        response = true;
      } else if (request.uri.path.endsWith('/rpc/kaladont_commit_turn')) {
        response = commitResult;
      } else if (request.uri.path.endsWith('/kaladont_sessions')) {
        response = sessionJson;
      } else if (request.uri.path.endsWith('/guild_player_rankings')) {
        response = [
          {
            'discord_user_id': 42,
            'username': 'Player',
            'score': 3,
            'avatar_url': null,
          },
        ];
      } else if (request.uri.path.endsWith('/discord_guilds')) {
        request.response.statusCode = HttpStatus.noContent;
      } else {
        response = [
          {'word': 'oniks'},
        ];
      }
      if (request.response.statusCode != HttpStatus.noContent) {
        request.response.write(jsonEncode(response));
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    dictionary = SupabaseDictionaryRepository(client);
    games = SupabaseGameRepository(client);
  });

  test(
    'dictionary validation uses a bounded query; count is server-side',
    () async {
      expect(await dictionary.contains('oniks'), isTrue);
      expect(requests.first.uri.queryParameters['word'], 'ilike.oniks');
      expect(requests.first.uri.queryParameters['limit'], '1');
      expect(await dictionary.countContinuations('on', {'oniks'}), 1005);
      expect(
        requests.last.uri.path,
        '/rest/v1/rpc/kaladont_count_continuations',
      );
      expect(jsonDecode(requests.last.body), {
        'p_prefix': 'on',
        'p_used_words': ['oniks'],
      });
    },
  );
  test(
    'empty random selection fails once rather than retrying indefinitely',
    () async {
      randomWord = null;
      await expectLater(
        dictionary.randomWord(),
        throwsA(isA<EmptyDictionaryException>()),
      );
      expect(requests, hasLength(1));
    },
  );
  test('random selection returns the RPC result', () async {
    expect(await dictionary.randomWord(), 'telefon');
  });
  test('dictionary failure is propagated', () async {
    fail = true;
    await expectLater(
      dictionary.contains('oniks'),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('session read is scoped to active guild and channel', () async {
    final session = await games.session(
      const GameKey(guildId: 7, channelId: 8),
    );
    expect(session!.revision, 2);
    expect(requests.single.uri.queryParameters['guild_id'], 'eq.7');
    expect(requests.single.uri.queryParameters['channel_id'], 'eq.8');
    expect(requests.single.uri.queryParameters['active'], 'eq.true');
  });
  test(
    'commit sends message id and expected version with score/state transaction',
    () async {
      final session = GameSession.fromJson(sessionJson);
      const guess = Guess(
        key: GameKey(guildId: 7, channelId: 8),
        messageId: 99,
        playerId: 42,
        username: 'Player',
        word: 'oniks',
      );
      expect(
        await games.commit(session, guess, victory: true, isDev: false),
        CommitResult.applied,
      );
      final params = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(params['p_message_id'], 99);
      expect(params['p_revision'], 2);
      expect(params['p_game_id'], session.gameId);
      expect(params['p_victory'], isTrue);
      expect(params['p_is_dev'], isFalse);
      commitResult = 'duplicate';
      expect(
        await games.commit(session, guess, victory: true, isDev: false),
        CommitResult.duplicate,
      );
    },
  );
  test(
    'guild upsert preserves enabled flag and rankings stay tenant scoped',
    () async {
      await games.upsertGuild(id: 7, name: 'Guild');
      expect(
        (jsonDecode(requests.first.body) as Map<String, dynamic>).containsKey(
          'enabled',
        ),
        isFalse,
      );
      final players = await games.ranking(7);
      expect(requests.last.uri.queryParameters['guild_id'], 'eq.7');
      expect(requests.last.uri.queryParameters['limit'], '25');
      expect(
        requests.last.uri.queryParameters['order'],
        'score.desc.nullslast,discord_user_id.asc.nullslast',
      );
      expect(players.single.id, 42);
      expect(players.single.avatarUrl, '');
    },
  );
}

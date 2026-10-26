import 'dart:convert';
import 'dart:io';

import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/channel_repository.dart';
import 'package:discord_bot/src/repository/retention_repository.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:discord_bot/src/services/game_service.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  late SupabaseClient client;
  late SupabaseDictionaryRepository dictionary;
  late SupabaseGameRepository games;
  late List<({String method, Uri uri, String body})> requests;
  Object? randomWord = 'telefon';
  bool fail = false;
  String turnStatus = 'applied';
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
    turnStatus = 'applied';
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
      } else if (request.uri.path.endsWith('/rpc/kaladont_guess')) {
        response = {'status': turnStatus, 'word': 'oniks', 'answers': 1};
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
      } else if (request.uri.path.endsWith('/rpc/kaladont_prune_receipts')) {
        response = 23;
      } else if (request.uri.path.endsWith('/kaladont_channels')) {
        final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
        response = List.generate(
          offset == 0 ? 500 : 1,
          (i) => {'guild_id': 7, 'channel_id': offset + i},
        );
      } else if (request.uri.path.endsWith(
        '/rpc/kaladont_set_channel_enabled',
      )) {
        request.response.statusCode = HttpStatus.noContent;
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
      dictionary.randomWord(),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('session read is scoped to active guild and channel', () async {
    final word = await games.currentWord(
      const GameKey(guildId: 7, channelId: 8),
    );
    expect(word, 'telefon');
    expect(requests.single.uri.queryParameters['select'], 'current_word');
    expect(requests.single.uri.queryParameters['guild_id'], 'eq.7');
    expect(requests.single.uri.queryParameters['channel_id'], 'eq.8');
    expect(requests.single.uri.queryParameters['active'], 'eq.true');
  });
  test(
    'accepted guess makes exactly one request with no session payload',
    () async {
      const guess = Guess(
        key: GameKey(guildId: 7, channelId: 8),
        messageId: 99,
        playerId: 42,
        username: 'Player',
        word: 'Oniks',
      );
      final service = GameService(dictionary: dictionary, games: games);
      expect((await service.guess(guess))!.type, ReplyType.correct);
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/rest/v1/rpc/kaladont_guess');
      expect(jsonDecode(requests.single.body), {
        'p_guild_id': 7,
        'p_channel_id': 8,
        'p_message_id': 99,
        'p_player_id': 42,
        'p_username': 'Player',
        'p_avatar_url': '',
        'p_word': 'oniks',
        'p_is_dev': false,
      });
      turnStatus = 'duplicate';
      expect(await service.guess(guess), isNull);
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
  test('channel cache bootstrap paginates beyond one page', () async {
    final channels = SupabaseChannelRepository(client);
    expect(await channels.enabledChannels(), hasLength(501));
    expect(requests, hasLength(2));
    expect(requests.last.uri.queryParameters['offset'], '500');
    expect(requests.first.uri.queryParameters['enabled'], 'eq.true');
    await channels.setEnabled(const GameKey(guildId: 7, channelId: 8), false);
    expect(jsonDecode(requests.last.body), {
      'p_guild_id': 7,
      'p_channel_id': 8,
      'p_enabled': false,
    });
  });
  test('retention uses a bounded server-side cleanup RPC', () async {
    expect(await SupabaseRetentionRepository(client).pruneBatch(), 23);
    expect(requests.single.uri.path, '/rest/v1/rpc/kaladont_prune_receipts');
    expect(jsonDecode(requests.single.body), {'p_batch_size': 1000});
  });
}

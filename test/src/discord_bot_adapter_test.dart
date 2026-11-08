// Discord-to-repository argument contracts, without a SupabaseClient.
// These do not assert HTTP/RPC names or p_* serialization: those belong to
// SupabaseGameRepository and cannot be verified by mocking GameRepository.
import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.bot.close());

  test(
    'command passes exact guild channel and word to start repository',
    () async {
      final other = TestContext(TestTextChannel(234), guildId: 567);
      h.dictionary.word = 'računalo';
      await h.command(using: other);
      expect(h.games.starts, [
        (const GameKey(guildId: 567, channelId: 234), 'računalo'),
      ]);
      expect(h.games.guilds, [(567, 'Test guild', null)]);
    },
  );

  test(
    'no current word requests one dictionary starter and one start',
    () async {
      await h.command();
      expect(h.games.calls, ['guild', 'current', 'start']);
      expect(h.dictionary.calls, 1);
      expect(h.games.starts, hasLength(1));
    },
  );

  test(
    'existing current word is returned without requesting a starter',
    () async {
      h.games.current = 'računalo';
      await h.command();
      expect(h.games.calls, ['guild', 'current']);
      expect(h.dictionary.calls, 0);
      expect(h.context.replies.single.content, endsWith('računalo'));
    },
  );

  test(
    'message preserves identifiers user metadata and normalized word',
    () async {
      await h.enable();
      await h.message(id: 123456789, text: '  ONIKS  ');
      final guess = h.games.guesses.single;
      expect(guess.key, key);
      expect(guess.messageId, 123456789);
      expect(guess.playerId, 2);
      expect(guess.username, 'Player');
      expect(guess.avatarUrl, 'https://example.invalid/avatar.png');
      expect(guess.word, 'oniks');
      expect(h.games.development, [false]);
    },
  );

  test(
    'guess path uses exactly one repository operation and no dictionary',
    () async {
      await h.enable();
      await h.message();
      expect(h.games.calls, ['guess']);
      expect(h.dictionary.calls, 0);
      expect(h.repository.writes, isEmpty);
    },
  );

  test(
    'concurrent-start loss returns already-started without retrying',
    () async {
      h.games.started = false;
      await h.command();
      expect(
        h.context.replies.single.content,
        'U ovom kanalu već je pokrenuta igra.',
      );
      expect(h.games.starts, hasLength(1));
      expect(h.dictionary.calls, 1);
    },
  );
}

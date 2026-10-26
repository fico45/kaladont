import 'package:test/test.dart';

import '../bin/kaladont/model/game_key.dart';
import '../bin/kaladont/model/game_session.dart';
import '../bin/kaladont/providers/game_state_provider.dart';

void main() {
  group('GameSessionsProvider', () {
    const firstChannel = GameKey(guildId: 1, channelId: 10);
    const secondChannel = GameKey(guildId: 1, channelId: 11);
    const otherGuild = GameKey(guildId: 2, channelId: 10);

    test('isolates sessions by guild and channel', () {
      final sessions = GameSessionsProvider();

      expect(
        sessions.start(const GameSession(
          key: firstChannel,
          currentWord: 'kaladont',
          usedWords: {'kaladont'},
        )),
        isTrue,
      );
      expect(
        sessions.start(const GameSession(
          key: secondChannel,
          currentWord: 'telefon',
          usedWords: {'telefon'},
        )),
        isTrue,
      );
      expect(
        sessions.start(const GameSession(
          key: otherGuild,
          currentWord: 'noga',
          usedWords: {'noga'},
        )),
        isTrue,
      );

      expect(sessions.state, hasLength(3));
      expect(sessions.sessionFor(firstChannel)?.currentWord, 'kaladont');
      expect(sessions.sessionFor(secondChannel)?.currentWord, 'telefon');
      expect(sessions.sessionFor(otherGuild)?.currentWord, 'noga');
    });

    test('does not replace an existing session', () {
      final sessions = GameSessionsProvider();
      const original = GameSession(
        key: firstChannel,
        currentWord: 'kaladont',
        usedWords: {'kaladont'},
      );

      expect(sessions.start(original), isTrue);
      expect(sessions.start(original), isFalse);
      expect(sessions.state, hasLength(1));
    });

    test('serializes only the session being processed', () {
      final sessions = GameSessionsProvider();
      sessions.start(const GameSession(
        key: firstChannel,
        currentWord: 'kaladont',
        usedWords: {'kaladont'},
      ));
      sessions.start(const GameSession(
        key: secondChannel,
        currentWord: 'telefon',
        usedWords: {'telefon'},
      ));

      expect(sessions.tryAcquire(firstChannel), isTrue);
      expect(sessions.tryAcquire(firstChannel), isFalse);
      expect(sessions.tryAcquire(secondChannel), isTrue);

      sessions.release(firstChannel);
      expect(sessions.tryAcquire(firstChannel), isTrue);
    });

    test('accepted words update only their session', () {
      final sessions = GameSessionsProvider();
      const first = GameSession(
        key: firstChannel,
        currentWord: 'telefon',
        usedWords: {'telefon'},
      );
      const second = GameSession(
        key: secondChannel,
        currentWord: 'noga',
        usedWords: {'noga'},
      );
      sessions.start(first);
      sessions.start(second);

      sessions.update(first.acceptWord(word: 'ontologija', playerId: 5));

      expect(sessions.sessionFor(firstChannel)?.currentWord, 'ontologija');
      expect(sessions.sessionFor(firstChannel)?.usedWords,
          {'telefon', 'ontologija'});
      expect(sessions.sessionFor(secondChannel)?.currentWord, 'noga');
    });
  });
}

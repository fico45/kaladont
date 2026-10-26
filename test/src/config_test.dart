import 'package:discord_bot/src/config.dart';
import 'package:discord_bot/src/discord_bot.dart';
import 'package:test/test.dart';

void main() {
  test('fails early for missing tokens or invalid database URL', () {
    expect(() => AppConfig.fromEnvironment({}), throwsFormatException);
    for (final url in ['relative', 'ftp://localhost', 'http://']) {
      expect(
        () => AppConfig.fromEnvironment({
          'supaBaseUrl': url,
          'supaBaseAPIKey': 'test',
          'discordToken': 'test',
        }),
        throwsFormatException,
      );
    }
  });
  test('loads runtime environment and development flag', () {
    final config = AppConfig.fromEnvironment({
      'supaBaseUrl': 'http://localhost:54331',
      'supaBaseAPIKey': 'test',
      'discordToken': 'test',
      'isDev': 'true',
    });
    expect(config.isDev, isTrue);
    expect(config.supabaseUrl, 'http://localhost:54331');
  });
  test('ignores DMs, bots and webhooks', () {
    expect(
      shouldProcessMessage(guildId: null, isBot: false, webhookId: null),
      isFalse,
    );
    expect(
      shouldProcessMessage(guildId: 1, isBot: true, webhookId: null),
      isFalse,
    );
    expect(
      shouldProcessMessage(guildId: 1, isBot: false, webhookId: 2),
      isFalse,
    );
    expect(
      shouldProcessMessage(guildId: 1, isBot: false, webhookId: null),
      isTrue,
    );
  });
}

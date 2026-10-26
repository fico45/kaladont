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
  test('filters DMs, bots, webhooks, disabled channels and shutdown', () {
    expect(
      messageIgnoreReason(guildId: null, isBot: false, webhookId: null),
      isNotNull,
    );
    expect(
      messageIgnoreReason(guildId: 1, isBot: true, webhookId: null),
      isNotNull,
    );
    expect(
      messageIgnoreReason(guildId: 1, isBot: false, webhookId: 2),
      isNotNull,
    );
    expect(
      messageIgnoreReason(guildId: 1, isBot: false, webhookId: null),
      isNull,
    );
    expect(
      messageIgnoreReason(
        guildId: 1,
        isBot: false,
        webhookId: null,
        channelEnabled: false,
      ),
      'disabledChannel',
    );
    expect(
      messageIgnoreReason(
        guildId: 1,
        isBot: false,
        webhookId: null,
        closing: true,
      ),
      'shuttingDown',
    );
  });
}

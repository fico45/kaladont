import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';

import 'model/game_key.dart';
import 'model/game_session.dart';
import 'providers/game_state_provider.dart';
import 'providers/saved_word_provider.dart';
import 'services/player_service.dart';
import 'services/server_service.dart';

class ChatCommands {
  static late final ProviderContainer container;

  ChatCommands({required ProviderContainer provider}) {
    container = provider;
  }

  static final ChatCommand kaladontStart = ChatCommand(
    'kaladont-start',
    'Započni novu igru Kaladonta',
    id('kaladont-start', (ChatContext context) async {
      final guild = context.guild;
      if (guild == null) {
        await context.respond(
          MessageBuilder(content: 'Kaladont se može igrati samo na serveru.'),
        );
        return;
      }

      final key = GameKey(
        guildId: guild.id.value,
        channelId: context.channel.id.value,
      );
      final sessions = container.read(gameSessionsProvider.notifier);
      if (sessions.sessionFor(key) != null) {
        await context.respond(MessageBuilder(
          content: 'U ovom kanalu već je pokrenuta igra.',
        ));
        return;
      }

      await ServerService.upsertGuild(guild);
      final randomWord =
          await container.read(savedWordProvider.notifier).getRandomWord();
      final started = sessions.start(GameSession(
        key: key,
        currentWord: randomWord,
        usedWords: {randomWord},
      ));

      await context.respond(MessageBuilder(
        content: started
            ? 'Nova igra kaladonta započeta! Početna riječ: $randomWord'
            : 'U ovom kanalu već je pokrenuta igra.',
      ));
    }),
  );

  static final ChatCommand kaladontHighScores = ChatCommand(
    'kaladont-ranks',
    'Rank lista Kaladont igre',
    id('kaladont-ranks', (ChatContext context) async {
      final guild = context.guild;
      if (guild == null) {
        await context.respond(
          MessageBuilder(content: 'Rank lista dostupna je samo na serveru.'),
        );
        return;
      }

      await ServerService.upsertGuild(guild);
      final players = await PlayerService.getGuildRanking(guild.id.value);
      final fields = players
          .map((player) => EmbedFieldBuilder(
                isInline: false,
                name: player.username,
                value: player.score.toString(),
              ))
          .toList();
      final embed = EmbedBuilder()
        ..color = DiscordColor.fromRgb(124, 252, 0)
        ..title = 'Rank lista Kaladont igre'
        ..description = players.isEmpty ? 'Još nema osvojenih bodova.' : null
        ..fields = fields;
      await context.respond(MessageBuilder(embeds: [embed]));
    }),
  );
}

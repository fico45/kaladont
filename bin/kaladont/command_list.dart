import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:riverpod/riverpod.dart';
import 'providers/game_state_provider.dart';
import 'providers/player_provider.dart';
import 'providers/saved_word_provider.dart';

class ChatCommands {
  static late final ProviderContainer container;
  ChatCommands({required ProviderContainer provider}) {
    container = provider;
  }
  static ChatCommand kaladontStart = ChatCommand(
      'kaladont-start',
      "Započni novu igru Kaladonta",
      id('kaladont-start', (ChatContext context) async {
        final gameState = container.read(gameStateProvider.notifier).state;
        final wordPrvider = container.read(savedWordProvider.notifier);
        if (gameState.isKaladontStarted) {
          context.respond(
            MessageBuilder(
              content:
                  'Ne možete započeti novu sesiju igre dok je već jedna u tijeku.',
            ),
          );
          return;
        }
        String randomWord = await wordPrvider.getRandomWord();

        gameState.isKaladontStarted = true;
        gameState.gameChannelId = context.channel.id.toString();

        context.respond(
          MessageBuilder(
            content: 'Nova igra kaladonta započeta! Početna riječ: $randomWord',
          ),
        );
      }));

  static ChatCommand kaladontHighScores = ChatCommand(
      'kaladont-ranks',
      'Rank lista Kaladont igre',
      id('kaladont-ranks', (ChatContext context) async {
        final players = container.read(playersProvider);
        container.read(playersProvider.notifier).sortPlayers();
        List<EmbedFieldBuilder> fields = [];
        for (var player in players) {
          fields.add(
            EmbedFieldBuilder(
              isInline: false,
              name: player.username,
              value: "${player.score}",
            ),
          );
        }
        EmbedBuilder newEmbed = EmbedBuilder()
          ..color = DiscordColor.fromRgb(124, 252, 0)
          ..title = "Rank lista Kaladont igre"
          ..fields = fields;
        final message = MessageBuilder(embeds: [newEmbed]);
        context.respond(message);
      }));
}

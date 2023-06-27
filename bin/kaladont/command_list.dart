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
      id('kaladont-start', (IChatContext context) async {
        final gameState = container.read(gameStateProvider.notifier).state;
        final wordPrvider = container.read(savedWordProvider.notifier);
        if (gameState.isKaladontStarted) {
          context.respond(MessageBuilder.content(
              'Ne možete započeti novu sesiju igre dok je već jedna u tijeku.'));
          return;
        }
        String randomWord = await wordPrvider.getRandomWord();

        gameState.isKaladontStarted = true;
        gameState.gameChannelId = context.channel.id.toString();

        context.respond(MessageBuilder.content(
            'Nova igra kaladonta započeta! Početna riječ: $randomWord'));
      }));

  static ChatCommand kaladontHighScores = ChatCommand(
      'kaladont-ranks',
      'Rank lista Kaladont igre',
      id('kaladont-ranks', (IChatContext context) async {
        final players = container.read(playersProvider);
        container.read(playersProvider.notifier).sortPlayers();
        List<EmbedFieldBuilder> fields = [];
        for (var player in players) {
          fields.add(EmbedFieldBuilder(
              "${player.username}  ${player.score.toString()}"));
        }
        EmbedBuilder newEmbed = EmbedBuilder()
          ..color = DiscordColor.green
          ..title = "Rank lista Kaladont igre"
          ..fields.addAll(fields);
        final message = MessageBuilder.embed(newEmbed);
        context.respond(message);
      }));
}

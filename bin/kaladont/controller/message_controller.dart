import 'package:nyxx/nyxx.dart';
import 'package:riverpod/riverpod.dart';

enum TypeOfMessage {
  correctGuess,
  failedGuess,
  startGame,
  endGame,
  warning,
  error,
}

class MessageController {
  static Future<void> sendMessage({
    required String message,
    required MessageCreateEvent event,
    required ProviderContainer providerContainer,
    required TypeOfMessage type,
  }) async {
    List<EmbedBuilder> embeds = [];
    final embedder = EmbedBuilder();
    embedder.title = _getMessageTitle(type);
    embedder.color = _getMessageColor(type);
    embedder.description = message;
    embeds.add(embedder);
    await event.message.channel.sendMessage(MessageBuilder(embeds: embeds));
  }

  static String _getMessageTitle(TypeOfMessage type) {
    switch (type) {
      case TypeOfMessage.correctGuess:
        return "Točan odgovor!";
      case TypeOfMessage.failedGuess:
        return "Krivi odgovor!";
      case TypeOfMessage.startGame:
        return "Nova igra započeta!";
      case TypeOfMessage.endGame:
        return "Igra završena!";
      case TypeOfMessage.warning:
        return "Ups!";
      case TypeOfMessage.error:
        return "Greška!";
      default:
        return "Nepoznata poruka";
    }
  }

  static DiscordColor _getMessageColor(TypeOfMessage type) {
    switch (type) {
      case TypeOfMessage.correctGuess:
        return DiscordColor.fromRgb(0, 255, 255);
      case TypeOfMessage.failedGuess:
        return DiscordColor.fromRgb(255, 0, 255);
      case TypeOfMessage.startGame:
        return DiscordColor.fromRgb(0, 255, 0);
      case TypeOfMessage.endGame:
        return DiscordColor.fromRgb(255, 255, 0);
      case TypeOfMessage.warning:
        return DiscordColor.fromRgb(255, 140, 0);
      case TypeOfMessage.error:
        return DiscordColor.fromRgb(255, 0, 0);
      default:
        return DiscordColor.fromRgb(0, 0, 255);
    }
  }
}

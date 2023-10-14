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
  static Future<IMessage> sendMessage({
    required String message,
    required IMessageReceivedEvent event,
    required ProviderContainer providerContainer,
    required TypeOfMessage type,
  }) async {
    final embedder = EmbedBuilder();
    embedder.title = _getMessageTitle(type);
    embedder.color = _getMessageColor(type);
    embedder.description = message;
    return await event.message.channel
        .sendMessage(MessageBuilder.embed(embedder));
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
        return DiscordColor.cornflowerBlue;
      case TypeOfMessage.failedGuess:
        return DiscordColor.rose;
      case TypeOfMessage.startGame:
        return DiscordColor.green;
      case TypeOfMessage.endGame:
        return DiscordColor.gold;
      case TypeOfMessage.warning:
        return DiscordColor.orange;
      case TypeOfMessage.error:
        return DiscordColor.red;
      default:
        return DiscordColor.blue;
    }
  }
}

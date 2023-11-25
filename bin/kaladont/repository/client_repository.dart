import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:supabase/supabase.dart';

import '../../consts.dart';
import '../command_list.dart';

class BotClient {
  static CommandsPlugin commands = CommandsPlugin(
    prefix: mentionOr((_) => '!'),
    options: CommandsOptions(logErrors: true, type: CommandType.slashOnly),
  )
    ..addCommand(ChatCommands.kaladontStart)
    ..addCommand(ChatCommands.kaladontHighScores);

  static final bot = Nyxx.connectGateway(
    Tokens.discordToken,
    GatewayIntents.messageContent | GatewayIntents.allUnprivileged,
    options: GatewayClientOptions(
      loggerName: 'KaladontBot',
      plugins: [
        Logging(),
        CliIntegration(),
        IgnoreExceptions(),
        commands,
      ],
    ),
  );
}

class SPC {
  static SupabaseClient client = SupabaseClient(
    Tokens.supabaseUrl,
    Tokens.supabaseApiKey,
  );
}

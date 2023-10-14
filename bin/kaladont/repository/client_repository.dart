
import 'package:nyxx/nyxx.dart';
import 'package:supabase/supabase.dart';

import '../../consts.dart';

class BotClient {
  static final bot = NyxxFactory.createNyxxWebsocket(
    Tokens.discordToken,
    GatewayIntents.messageContent | GatewayIntents.allUnprivileged,
  );
}

class SPC {
  static SupabaseClient client = SupabaseClient(
    Tokens.supabaseUrl,
    Tokens.supabaseApiKey,
  );
}

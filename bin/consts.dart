import 'package:dotenv/dotenv.dart';

class Globals {
  static const String supabaseFilter = '("imenica","glagol","pridjev")';
  static List<String> usedWords = [];
  static const chars =
      'AaBbCcĆćČčDdĐđEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsŠšTtUuVvZzŽž';
}

class Tokens {
  static String supabaseUrl = '';
  static String supabaseApiKey = '';

  static String discordToken = '';

  static void loadTokens() {
    var env = DotEnv(includePlatformEnvironment: true)..load();
    supabaseUrl = env['supaBaseUrl'] ?? '';
    supabaseApiKey = env['supaBaseAPIKey'] ?? '';
    discordToken = env['discordToken'] ?? '';
  }
}

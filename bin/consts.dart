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
  static bool isDev = false;

  static void loadTokens() {
    var env = DotEnv(includePlatformEnvironment: true)..load();
    supabaseUrl = bool.hasEnvironment('supaBaseUrl')
        ? const String.fromEnvironment('supaBaseUrl')
        : env['supaBaseUrl'] ?? '';
    supabaseApiKey = bool.hasEnvironment('supaBaseAPIKey')
        ? const String.fromEnvironment('supaBaseAPIKey')
        : env['supaBaseAPIKey'] ?? '';
    discordToken = bool.hasEnvironment('discordToken')
        ? const String.fromEnvironment('discordToken')
        : env['discordToken'] ?? '';
    isDev = bool.hasEnvironment('isDev')
        ? const bool.fromEnvironment('isDev')
        : env['isDev'] == 'true';
  }
}

import 'dart:io';

final class AppConfig {
  final String supabaseUrl;
  final String supabaseApiKey;
  final String discordToken;
  final bool isDev;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseApiKey,
    required this.discordToken,
    this.isDev = false,
  });

  factory AppConfig.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final config = AppConfig(
      supabaseUrl: bool.hasEnvironment('supaBaseUrl')
          ? const String.fromEnvironment('supaBaseUrl')
          : env['supaBaseUrl'] ?? '',
      supabaseApiKey: bool.hasEnvironment('supaBaseAPIKey')
          ? const String.fromEnvironment('supaBaseAPIKey')
          : env['supaBaseAPIKey'] ?? '',
      discordToken: bool.hasEnvironment('discordToken')
          ? const String.fromEnvironment('discordToken')
          : env['discordToken'] ?? '',
      isDev: bool.hasEnvironment('isDev')
          ? const bool.fromEnvironment('isDev')
          : env['isDev'] == 'true',
    );
    config.validate();
    return config;
  }

  void validate() {
    final url = Uri.tryParse(supabaseUrl);
    if (url == null ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        !{'http', 'https'}.contains(url.scheme)) {
      throw const FormatException('supaBaseUrl must be an HTTP(S) URL.');
    }
    if (supabaseApiKey.trim().isEmpty || discordToken.trim().isEmpty) {
      throw const FormatException(
        'supaBaseAPIKey and discordToken are required.',
      );
    }
  }
}

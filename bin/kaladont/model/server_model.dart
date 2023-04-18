class DiscordServer {
  int id;
  String name;
  String serverImageUrl;

  DiscordServer(
      {required this.id, required this.name, required this.serverImageUrl});

  factory DiscordServer.fromJson(Map<String, dynamic> json) {
    return DiscordServer(
      id: json['id'],
      name: json['name'],
      serverImageUrl: json['server_image_url'],
    );
  }
}

/// A validated connection to a Jellyfin server, produced by the connect
/// screen and handed to the login screen. Not yet authenticated.
class ServerConnection {
  final String baseUrl;
  final String? serverName;
  final String? serverId;
  final String? version;

  const ServerConnection({
    required this.baseUrl,
    this.serverName,
    this.serverId,
    this.version,
  });
}

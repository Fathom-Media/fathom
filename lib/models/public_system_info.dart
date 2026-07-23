/// Response from `GET /System/Info/Public` — the unauthenticated endpoint
/// used to validate that a given address is a reachable Jellyfin server.
class PublicSystemInfo {
  final String? localAddress;
  final String? serverName;
  final String? version;
  final String? productName;
  final String? id;
  final bool? startupWizardCompleted;

  const PublicSystemInfo({
    this.localAddress,
    this.serverName,
    this.version,
    this.productName,
    this.id,
    this.startupWizardCompleted,
  });

  factory PublicSystemInfo.fromJson(Map<String, dynamic> json) {
    return PublicSystemInfo(
      localAddress: json['LocalAddress'] as String?,
      serverName: json['ServerName'] as String?,
      version: json['Version'] as String?,
      productName: json['ProductName'] as String?,
      id: json['Id'] as String?,
      startupWizardCompleted: json['StartupWizardCompleted'] as bool?,
    );
  }
}

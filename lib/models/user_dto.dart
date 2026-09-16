/// A Jellyfin user, as returned inside an authentication result.
class UserDto {
  final String id;
  final String name;
  final String? serverId;
  final String? primaryImageTag;
  final bool isAdministrator;
  final bool enableContentDeletion;

  /// Allowed to search for and download subtitles from the server's subtitle
  /// providers. Administrators always may.
  final bool enableSubtitleManagement;

  const UserDto({
    required this.id,
    required this.name,
    this.serverId,
    this.primaryImageTag,
    this.isAdministrator = false,
    this.enableContentDeletion = false,
    this.enableSubtitleManagement = false,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) {
    final policy =
        (json['Policy'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UserDto(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Unknown',
      serverId: json['ServerId'] as String?,
      primaryImageTag: json['PrimaryImageTag'] as String?,
      isAdministrator: policy['IsAdministrator'] as bool? ?? false,
      enableContentDeletion: policy['EnableContentDeletion'] as bool? ?? false,
      enableSubtitleManagement:
          policy['EnableSubtitleManagement'] as bool? ?? false,
    );
  }
}

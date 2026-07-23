/// A Jellyfin user, as returned inside an authentication result.
class UserDto {
  final String id;
  final String name;
  final String? serverId;
  final String? primaryImageTag;
  final bool isAdministrator;
  final bool enableContentDeletion;

  const UserDto({
    required this.id,
    required this.name,
    this.serverId,
    this.primaryImageTag,
    this.isAdministrator = false,
    this.enableContentDeletion = false,
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
    );
  }
}

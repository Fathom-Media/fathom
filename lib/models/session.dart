/// An authenticated session: everything needed to make API calls and to
/// restore login across app restarts. Persisted (encrypted) via the accounts
/// store in the OS secret store.
class Session {
  final String baseUrl;
  final String accessToken;
  final String userId;
  final String userName;
  final String? serverName;
  final String? serverId;
  final bool isAdmin;
  final bool canDelete;

  const Session({
    required this.baseUrl,
    required this.accessToken,
    required this.userId,
    required this.userName,
    this.serverName,
    this.serverId,
    this.isAdmin = false,
    this.canDelete = false,
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'userId': userId,
        'userName': userName,
        'serverName': serverName,
        'serverId': serverId,
        'isAdmin': isAdmin,
        'canDelete': canDelete,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        baseUrl: json['baseUrl'] as String,
        accessToken: json['accessToken'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        serverName: json['serverName'] as String?,
        serverId: json['serverId'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
        canDelete: json['canDelete'] as bool? ?? false,
      );
}

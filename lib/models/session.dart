/// An authenticated session: everything needed to make API calls and to
/// restore login across app restarts. Persisted (encrypted) via the accounts
/// store in the OS secret store.
class Session {
  /// The address currently in use for requests/images/streams. This is the
  /// RESOLVED active address: the resolver swaps it between [internalUrl] and
  /// [externalUrl] as the home network comes and goes. Account identity keys on
  /// server id + user (see accountKey), so this can float without forking.
  final String baseUrl;
  final String accessToken;
  final String userId;
  final String userName;
  final String? serverName;
  final String? serverId;
  final bool isAdmin;
  final bool canDelete;

  /// Optional home/LAN address. When both this and [externalUrl] are set, the
  /// resolver prefers this whenever it's reachable. Null = single-address mode.
  final String? internalUrl;

  /// Optional remote/WAN address, used when [internalUrl] isn't reachable. Set
  /// alongside [internalUrl] when the user configures dual addresses.
  final String? externalUrl;

  const Session({
    required this.baseUrl,
    required this.accessToken,
    required this.userId,
    required this.userName,
    this.serverName,
    this.serverId,
    this.isAdmin = false,
    this.canDelete = false,
    this.internalUrl,
    this.externalUrl,
  });

  Session copyWith({
    String? baseUrl,
    String? accessToken,
    String? userId,
    String? userName,
    String? serverName,
    String? serverId,
    bool? isAdmin,
    bool? canDelete,
    // Address fields are nullable and clearable, so a sentinel distinguishes
    // "leave unchanged" (omit) from "set to null" (explicit).
    Object? internalUrl = _unset,
    Object? externalUrl = _unset,
  }) =>
      Session(
        baseUrl: baseUrl ?? this.baseUrl,
        accessToken: accessToken ?? this.accessToken,
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        serverName: serverName ?? this.serverName,
        serverId: serverId ?? this.serverId,
        isAdmin: isAdmin ?? this.isAdmin,
        canDelete: canDelete ?? this.canDelete,
        internalUrl: internalUrl == _unset
            ? this.internalUrl
            : internalUrl as String?,
        externalUrl: externalUrl == _unset
            ? this.externalUrl
            : externalUrl as String?,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'userId': userId,
        'userName': userName,
        'serverName': serverName,
        'serverId': serverId,
        'isAdmin': isAdmin,
        'canDelete': canDelete,
        'internalUrl': internalUrl,
        'externalUrl': externalUrl,
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
        internalUrl: json['internalUrl'] as String?,
        externalUrl: json['externalUrl'] as String?,
      );
}

/// Sentinel for [Session.copyWith] to tell "omit" apart from "set to null".
const Object _unset = Object();

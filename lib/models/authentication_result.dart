import 'user_dto.dart';

/// Response from `POST /Users/AuthenticateByName`.
class AuthenticationResult {
  final String accessToken;
  final String serverId;
  final UserDto user;

  const AuthenticationResult({
    required this.accessToken,
    required this.serverId,
    required this.user,
  });

  factory AuthenticationResult.fromJson(Map<String, dynamic> json) {
    return AuthenticationResult(
      accessToken: json['AccessToken'] as String,
      serverId: json['ServerId'] as String? ?? '',
      user: UserDto.fromJson(json['User'] as Map<String, dynamic>),
    );
  }
}

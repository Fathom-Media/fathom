part of 'jellyfin_client.dart';

/// Connecting to a server and signing in: reachability, public info, password login and Quick Connect.
extension JellyfinAuthApi on JellyfinClient {
/// A quick yes/no on whether the server answers, for the offline check. Uses
  /// the unauthenticated /System/Info/Public with a short timeout: a reachable
  /// server replies in milliseconds, so a slow failure means offline. Never
  /// throws, offline is an answer.
  Future<bool> pingServer(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final probe = Dio(
      BaseOptions(connectTimeout: timeout, receiveTimeout: timeout),
    );
    try {
      final res = await probe.get('$baseUrl/System/Info/Public');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      probe.close();
    }
  }

/// Resolves a user-typed server address to a reachable base URL and its public
  /// info. When the user omits the scheme, tries `https://` then `http://` (home
  /// servers on a LAN IP are usually plain http), each with a short timeout so a
  /// dead scheme fails fast. This is why a user can type `10.0.1.3:8096` without
  /// the `http://`. If a scheme was typed, it's honoured as-is.
  Future<({String baseUrl, PublicSystemInfo info})> resolvePublicServer(
    String input,
  ) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw JellyfinException('Please enter a server address.');
    }
    final hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    final candidates = <String>[];
    if (hasScheme) {
      candidates.add(JellyfinClient.normalizeBaseUrl(trimmed));
    } else {
      final host = trimmed.replaceAll(RegExp(r'/+$'), '');
      candidates
        ..add('https://$host')
        ..add('http://$host');
    }
    final probe = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    JellyfinException? lastErr;
    try {
      for (final url in candidates) {
        try {
          final res = await probe.get('$url/System/Info/Public');
          final data = res.data;
          if (data is Map) {
            return (
              baseUrl: url,
              info: PublicSystemInfo.fromJson(Map<String, dynamic>.from(data)),
            );
          }
          lastErr = JellyfinException(
            'That address did not return a Jellyfin server response.',
          );
        } on DioException catch (e) {
          lastErr = JellyfinException(_friendlyDioError(e, connecting: true));
        }
      }
    } finally {
      probe.close();
    }
    throw lastErr ?? JellyfinException('Could not reach that server.');
  }

/// Validates that [baseUrl] points at a reachable Jellyfin server.
  Future<PublicSystemInfo> getPublicSystemInfo(String baseUrl) async {
    try {
      final res = await _dio.get('$baseUrl/System/Info/Public');
      final data = res.data;
      if (data is! Map) {
        throw JellyfinException(
          'That address did not return a Jellyfin server response.',
        );
      }
      return PublicSystemInfo.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e, connecting: true));
    }
  }

/// Authenticates with username + password.
  Future<AuthenticationResult> authenticateByName({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(
          headers: {
            'Authorization': authHeader(),
            'Content-Type': 'application/json',
          },
        ),
      );
      return AuthenticationResult.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw JellyfinException('Incorrect username or password.');
      }
      throw JellyfinException(_friendlyDioError(e));
    }
  }

/// Whether the server has Quick Connect turned on.
  Future<bool> quickConnectEnabled(String baseUrl) async {
    try {
      final res = await _dio.get('$baseUrl/QuickConnect/Enabled');
      return res.data == true || res.data == 'true';
    } on DioException {
      return false;
    }
  }

/// Starts a Quick Connect request; returns the code to show the user and the
  /// secret to poll with.
  Future<({String secret, String code})> quickConnectInitiate(
    String baseUrl,
  ) async {
    try {
      final res = await _dio.get(
        '$baseUrl/QuickConnect/Initiate',
        options: Options(headers: {'Authorization': authHeader()}),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return (secret: data['Secret'] as String, code: data['Code'] as String);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

/// Polls a pending Quick Connect request; true once the user has approved it
  /// on an already-signed-in device.
  Future<bool> quickConnectPoll(String baseUrl, String secret) async {
    try {
      final res = await _dio.get(
        '$baseUrl/QuickConnect/Connect',
        queryParameters: {'secret': secret},
        options: Options(headers: {'Authorization': authHeader()}),
      );
      final data = res.data;
      return data is Map && data['Authenticated'] == true;
    } on DioException catch (e) {
      // 404 means the request expired or was cancelled server-side.
      if (e.response?.statusCode == 404) {
        throw JellyfinException('This Quick Connect request expired.');
      }
      throw JellyfinException(_friendlyDioError(e));
    }
  }

/// Approves a Quick Connect code entered on another device (as the signed-in
  /// user). Returns true if the code was accepted.
  Future<bool> authorizeQuickConnect({
    required String baseUrl,
    required String token,
    required String code,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/QuickConnect/Authorize',
        queryParameters: {'code': code},
        options: _authed(token),
      );
      return res.data == true || res.data == 'true';
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw JellyfinException('That code was not found or has expired.');
      }
      throw JellyfinException(_friendlyDioError(e));
    }
  }

/// Exchanges an approved Quick Connect secret for an access token.
  Future<AuthenticationResult> authenticateWithQuickConnect({
    required String baseUrl,
    required String secret,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Users/AuthenticateWithQuickConnect',
        data: {'Secret': secret},
        options: Options(
          headers: {
            'Authorization': authHeader(),
            'Content-Type': 'application/json',
          },
        ),
      );
      return AuthenticationResult.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

Options _authed(String token) =>
      Options(headers: {'Authorization': authHeader(token: token)});
}

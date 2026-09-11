import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import '../models/authentication_result.dart';
import '../models/base_item.dart';
import '../models/items_result.dart';
import '../models/media_segment.dart';
import '../models/public_system_info.dart';
import '../models/user_dto.dart';
import '../models/lyrics.dart';
import '../services/diagnostics.dart';
import '../services/tv_mode.dart';

part 'jellyfin_admin.dart';
part 'jellyfin_auth.dart';
part 'jellyfin_library.dart';
part 'jellyfin_livetv.dart';
part 'jellyfin_sessions.dart';
part 'jellyfin_streaming.dart';

/// A user-facing error carrying a message safe to show in the UI.
class JellyfinException implements Exception {
  final String message;
  JellyfinException(this.message);
  @override
  String toString() => message;
}

/// An opened live stream: the playable URL plus the ids needed to close it and
/// release the tuner.
class LiveStreamHandle {
  final String url;
  final String? liveStreamId;
  final String? playSessionId;
  const LiveStreamHandle({
    required this.url,
    this.liveStreamId,
    this.playSessionId,
  });
}

/// Thin, typed Jellyfin API client. Grows per phase; for now it covers the
/// connect + login surface. All auth uses the MediaBrowser Authorization
/// header scheme that Jellyfin expects.

class JellyfinClient {
final String deviceId;

final String clientName;

final String clientVersion;

final Dio _dio;

/// [httpClient] is for tests, which swap in an adapter to inspect what
  /// actually goes over the wire. Production leaves it null.
  JellyfinClient({
    required this.deviceId,
    this.clientName = 'Fathom',
    this.clientVersion = '0.1.0',
    Dio? httpClient,
  }) : _dio =
           httpClient ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );

/// Builds the `Authorization` header. Include [token] once authenticated.
  String authHeader({String? token}) {
    final parts = <String>[
      'MediaBrowser Client="$clientName"',
      'Device="Linux"',
      'DeviceId="$deviceId"',
      'Version="$clientVersion"',
    ];
    if (token != null) parts.add('Token="$token"');
    return parts.join(', ');
  }

/// Normalizes user-entered addresses: adds https:// if no scheme is given,
  /// trims whitespace and trailing slashes.
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) {
      throw JellyfinException('Please enter a server address.');
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }

String _friendlyDioError(DioException e, {bool connecting = false}) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Check the address and '
            'that the server is running.';
      case DioExceptionType.connectionError:
        return connecting
            ? 'Could not reach that server. Check the address, port, and your '
                  'network connection.'
            : 'Lost connection to the server.';
      case DioExceptionType.badCertificate:
        return "The server's security certificate could not be verified.";
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) {
          return connecting
              ? 'No Jellyfin server was found at that address.'
              : 'The requested resource was not found (404).';
        }
        return 'The server returned an error (${code ?? 'unknown'}).';
      default:
        return 'Something went wrong talking to the server.';
    }
  }
}

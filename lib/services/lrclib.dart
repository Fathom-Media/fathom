import 'package:dio/dio.dart';

import '../models/lyrics.dart';

/// LrcLib: free, open, no key. Looks up lyrics by track metadata.
///
/// Used only as a fallback when the Jellyfin server has none of its own. It's
/// the same source Jellyfin's lyric plugin uses, so going direct just skips a
/// plugin the server may not have installed.
class LrcLib {
  LrcLib({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              // LrcLib asks clients to identify themselves.
              headers: {
                'User-Agent':
                    'Fathom (https://github.com/thebigjoe1/fathom)',
              },
            ));

  final Dio _dio;

  static const _endpoint = 'https://lrclib.net/api/get';

  /// Lyrics for a track, or null if LrcLib doesn't have them.
  ///
  /// The exact-match endpoint keys on artist, title, album and duration. The
  /// duration matters: it's how LrcLib tells two songs of the same name apart,
  /// so a wrong length returns nothing rather than the wrong words.
  Future<SongLyrics?> lookup({
    required String artist,
    required String title,
    String? album,
    Duration? duration,
  }) async {
    if (artist.isEmpty || title.isEmpty) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _endpoint,
        queryParameters: {
          'artist_name': artist,
          'track_name': title,
          if (album != null && album.isNotEmpty) 'album_name': album,
          if (duration != null) 'duration': duration.inSeconds,
        },
        options: Options(validateStatus: (s) => s == 200 || s == 404),
      );
      if (res.statusCode == 404 || res.data == null) return null;

      final data = res.data!;
      // An instrumental track genuinely has no lyrics, and LrcLib flags it —
      // worth honouring rather than showing an empty view.
      if (data['instrumental'] == true) return null;

      final synced = '${data['syncedLyrics'] ?? ''}';
      if (synced.isNotEmpty) return parseLrc(synced);

      // Fall back to plain lyrics when there's no timed version.
      final plain = '${data['plainLyrics'] ?? ''}';
      if (plain.isNotEmpty) return parseLrc(plain);
      return null;
    } on DioException {
      // A lookup that fails is no worse than a track that has no lyrics.
      return null;
    }
  }
}

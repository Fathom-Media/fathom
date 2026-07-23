/// A genre from Seerr's genre slider, carrying a few backdrop images so the
/// card can show artwork behind the name (as the Jellyseerr web app does).
class SeerrGenre {
  final int id;
  final String name;
  final String mediaType; // 'movie' | 'tv'
  final List<String> backdrops; // TMDB backdrop paths or full URLs

  const SeerrGenre({
    required this.id,
    required this.name,
    required this.mediaType,
    this.backdrops = const [],
  });

  /// The first backdrop as a full URL. Jellyseerr returns TMDB paths (a leading
  /// slash), but some builds return absolute URLs, so both are handled.
  String? get backdropUrl {
    if (backdrops.isEmpty) return null;
    final b = backdrops.first;
    if (b.startsWith('http')) return b;
    return 'https://image.tmdb.org/t/p/w780$b';
  }

  factory SeerrGenre.fromJson(Map<String, dynamic> j, String mediaType) =>
      SeerrGenre(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        mediaType: mediaType,
        backdrops: [
          for (final b in (j['backdrops'] as List?) ?? const [])
            if (b is String && b.isNotEmpty) b,
        ],
      );
}

/// A lightweight reference to a media item from Seerr's `/media` endpoint
/// (Recently Added). It carries only ids and status; the poster and title are
/// filled in per-card from the detail endpoint.
class SeerrMediaRef {
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final int? status;

  const SeerrMediaRef({
    required this.tmdbId,
    required this.mediaType,
    this.status,
  });

  factory SeerrMediaRef.fromJson(Map<String, dynamic> j) => SeerrMediaRef(
        tmdbId: (j['tmdbId'] as num?)?.toInt() ?? 0,
        mediaType: j['mediaType'] as String? ?? '',
        status: (j['status'] as num?)?.toInt(),
      );
}

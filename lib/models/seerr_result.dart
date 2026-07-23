/// A discover/search result from Seerr (backed by TMDB).
class SeerrResult {
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final int? status; // mediaInfo.status: 1 unknown,2 pending,3 processing,4 partial,5 available
  final double? voteAverage;

  const SeerrResult({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.status,
    this.voteAverage,
  });

  String? get posterUrl =>
      posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : null;
  String? get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w780$backdropPath'
      : null;

  bool get isRequested => status != null && status! >= 2;

  /// Nothing on the server and no request yet — so the Request action applies.
  bool get canRequest => !isRequested && !isAvailable;
  bool get isAvailable => status == 5;

  factory SeerrResult.fromJson(Map<String, dynamic> j) => SeerrResult(
        tmdbId: (j['id'] as num?)?.toInt() ?? 0,
        mediaType: j['mediaType'] as String? ?? 'movie',
        title: (j['title'] ?? j['name'] ?? '') as String,
        overview: j['overview'] as String?,
        posterPath: j['posterPath'] as String?,
        backdropPath: j['backdropPath'] as String?,
        status: (j['mediaInfo'] as Map?)?['status'] as int?,
        voteAverage: (j['voteAverage'] as num?)?.toDouble(),
      );
}

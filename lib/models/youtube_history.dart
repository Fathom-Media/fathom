/// A watched YouTube video: enough to render a history row and to resume.
class YoutubeHistoryEntry {
  final String id;
  final String title;
  final String author;
  final String? channelId;
  final int positionSeconds;
  final int durationSeconds;
  final int watchedAtMs; // epoch millis of the last watch

  const YoutubeHistoryEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.watchedAtMs,
    this.channelId,
  });

  Duration get position => Duration(seconds: positionSeconds);
  String get url => 'https://www.youtube.com/watch?v=$id';
  String get thumbnailUrl => 'https://img.youtube.com/vi/$id/mqdefault.jpg';

  /// How far through, 0..1. Zero when the duration isn't known yet.
  double get progress => durationSeconds <= 0
      ? 0
      : (positionSeconds / durationSeconds).clamp(0.0, 1.0);

  /// Treat the last few percent as finished, so credits don't leave a video
  /// sitting at "almost done" forever.
  bool get finished => progress >= 0.97;

  YoutubeHistoryEntry copyWith({
    int? positionSeconds,
    int? durationSeconds,
    int? watchedAtMs,
  }) =>
      YoutubeHistoryEntry(
        id: id,
        title: title,
        author: author,
        channelId: channelId,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        watchedAtMs: watchedAtMs ?? this.watchedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'channelId': channelId,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'watchedAtMs': watchedAtMs,
      };

  factory YoutubeHistoryEntry.fromJson(Map<String, dynamic> j) =>
      YoutubeHistoryEntry(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        channelId: j['channelId'] as String?,
        positionSeconds: (j['positionSeconds'] as num?)?.toInt() ?? 0,
        durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
        watchedAtMs: (j['watchedAtMs'] as num?)?.toInt() ?? 0,
      );
}

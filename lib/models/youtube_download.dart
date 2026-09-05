/// Where a download has got to.
enum YtDownloadStatus { queued, downloading, merging, done, failed, cancelled }

/// One download, live or finished.
class YoutubeDownload {
  final String id; // video id
  final String title;
  final String author;
  final String thumbnailUrl;
  final YtDownloadStatus status;

  /// 0..1, or null while the size is unknown or during the merge, which has no
  /// meaningful progress of its own.
  final double? progress;

  final String stage; // 'video' | 'audio' | 'merging'
  final String? filePath; // set once done
  final String? error; // set when failed
  final int bytes; // received so far, for a human-readable size

  /// Local-only playback position, so reopening a downloaded video resumes
  /// where you left off — mirrors the Jellyfin downloads' local watched
  /// state rather than the online watch-history system, which records a
  /// streaming URL a downloaded file should never touch.
  final int watchPositionSeconds;
  final int watchDurationSeconds;

  const YoutubeDownload({
    required this.id,
    required this.title,
    this.author = '',
    this.thumbnailUrl = '',
    this.status = YtDownloadStatus.queued,
    this.progress,
    this.stage = '',
    this.filePath,
    this.error,
    this.bytes = 0,
    this.watchPositionSeconds = 0,
    this.watchDurationSeconds = 0,
  });

  Duration get watchPosition => Duration(seconds: watchPositionSeconds);

  /// Treat the last few percent as finished, so credits don't leave a video
  /// sitting at "almost done" forever. Matches the online history's rule.
  bool get watchFinished =>
      watchDurationSeconds > 0 &&
      watchPositionSeconds / watchDurationSeconds >= 0.97;

  bool get isActive =>
      status == YtDownloadStatus.queued ||
      status == YtDownloadStatus.downloading ||
      status == YtDownloadStatus.merging;

  YoutubeDownload copyWith({
    YtDownloadStatus? status,
    double? progress,
    String? stage,
    String? filePath,
    String? error,
    int? bytes,
    int? watchPositionSeconds,
    int? watchDurationSeconds,
    bool clearProgress = false,
  }) =>
      YoutubeDownload(
        id: id,
        title: title,
        author: author,
        thumbnailUrl: thumbnailUrl,
        status: status ?? this.status,
        progress: clearProgress ? null : (progress ?? this.progress),
        stage: stage ?? this.stage,
        filePath: filePath ?? this.filePath,
        error: error ?? this.error,
        bytes: bytes ?? this.bytes,
        watchPositionSeconds: watchPositionSeconds ?? this.watchPositionSeconds,
        watchDurationSeconds: watchDurationSeconds ?? this.watchDurationSeconds,
      );

  /// Only completed downloads are stored: an interrupted one has no partial
  /// file to resume, so remembering it would just be a dead row.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'filePath': filePath,
        'bytes': bytes,
        'watchPositionSeconds': watchPositionSeconds,
        'watchDurationSeconds': watchDurationSeconds,
      };

  factory YoutubeDownload.fromJson(Map<String, dynamic> j) => YoutubeDownload(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
        watchPositionSeconds: (j['watchPositionSeconds'] as num?)?.toInt() ?? 0,
        watchDurationSeconds: (j['watchDurationSeconds'] as num?)?.toInt() ?? 0,
        status: YtDownloadStatus.done,
        filePath: j['filePath'] as String?,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      );

  String get sizeLabel {
    if (bytes <= 0) return '';
    const mb = 1024 * 1024;
    if (bytes >= 1024 * mb) {
      return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }
}

import '../l10n/generated/app_localizations.dart';

/// A YouTube search result, trimmed to what the list needs.
class YoutubeVideo {
  final String id;
  final String title;
  final String author; // channel name
  final String? channelId;
  final Duration? duration; // null for live streams
  final String thumbnailUrl;
  final int? viewCount;
  final DateTime? uploadDate;

  /// Search results carry a pre-rendered age ("5 years ago") instead of a date.
  final String? uploadedLabel;

  /// A Short. They carry no duration, and neither do live streams, so without
  /// this every Short renders with a red LIVE badge.
  final bool isShort;
  final String url;

  const YoutubeVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.url,
    required this.thumbnailUrl,
    this.channelId,
    this.duration,
    this.viewCount,
    this.uploadDate,
    this.uploadedLabel,
    this.isShort = false,
  });

  /// How long ago this was uploaded, from whichever source we have.
  String uploadedText(AppLocalizations l, DateTime now) =>
      uploadedLabel ?? agoLabel(l, now);

  bool get isLive => duration == null && !isShort;

  String durationLabel(AppLocalizations l) {
    final d = duration;
    if (d == null) return isShort ? l.miscVideoShort : l.extraBadgeLive;
    final h = d.inHours;
    final mm = (d.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Rough "3 days ago" style label for feed rows.
  String agoLabel(AppLocalizations l, DateTime now) {
    final d = uploadDate;
    if (d == null) return '';
    final diff = now.difference(d);
    if (diff.inDays >= 365) {
      return l.miscYearsAgo(diff.inDays ~/ 365);
    }
    if (diff.inDays >= 30) {
      return l.miscMonthsAgo(diff.inDays ~/ 30);
    }
    if (diff.inDays >= 1) {
      return l.miscDaysAgo(diff.inDays);
    }
    if (diff.inHours >= 1) {
      return l.miscHoursAgo(diff.inHours);
    }
    return l.miscJustNow;
  }

  String viewsLabel(AppLocalizations l) {
    final v = viewCount;
    if (v == null || v <= 0) return '';
    final String n;
    if (v >= 1000000000) {
      n = '${(v / 1000000000).toStringAsFixed(1)}B';
    } else if (v >= 1000000) {
      n = '${(v / 1000000).toStringAsFixed(1)}M';
    } else if (v >= 1000) {
      n = '${(v / 1000).toStringAsFixed(1)}K';
    } else {
      n = '$v';
    }
    return l.miscViews(n);
  }

  /// Stored in local playlists, so a saved video renders without a network
  /// round-trip. uploadedLabel is kept as-is rather than recomputed: it's
  /// YouTube's own wording, and the absolute date isn't always available.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'url': url,
        'thumbnailUrl': thumbnailUrl,
        'channelId': channelId,
        'durationMs': duration?.inMilliseconds,
        'viewCount': viewCount,
        'uploadDate': uploadDate?.toIso8601String(),
        'uploadedLabel': uploadedLabel,
        'isShort': isShort,
      };

  factory YoutubeVideo.fromJson(Map<String, dynamic> j) {
    final ms = (j['durationMs'] as num?)?.toInt();
    final date = j['uploadDate'] as String?;
    return YoutubeVideo(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      author: j['author'] as String? ?? '',
      url: j['url'] as String? ??
          'https://www.youtube.com/watch?v=${j['id'] ?? ''}',
      thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
      channelId: j['channelId'] as String?,
      duration: ms == null ? null : Duration(milliseconds: ms),
      viewCount: (j['viewCount'] as num?)?.toInt(),
      uploadDate: date == null ? null : DateTime.tryParse(date),
      uploadedLabel: j['uploadedLabel'] as String?,
      isShort: j['isShort'] as bool? ?? false,
    );
  }
}

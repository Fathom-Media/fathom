import '../l10n/generated/app_localizations.dart';
import 'youtube_video.dart';

/// A playlist you made, stored on this device.
///
/// Distinct from a YouTube playlist found in search: that one belongs to
/// someone else and is fetched live, this one is yours and never leaves the
/// machine. NewPipe draws the same line, and it's the only kind we can offer
/// without an account.
class YoutubeLocalPlaylist {
  final String id;
  final String name;
  final List<YoutubeVideo> videos;

  const YoutubeLocalPlaylist({
    required this.id,
    required this.name,
    this.videos = const [],
  });

  /// The first video's thumbnail stands in for the playlist's cover.
  String get thumbnailUrl => videos.isEmpty ? '' : videos.first.thumbnailUrl;

  String countLabel(AppLocalizations l) => l.miscVideoCount(videos.length);

  bool contains(String videoId) => videos.any((v) => v.id == videoId);

  YoutubeLocalPlaylist copyWith({String? name, List<YoutubeVideo>? videos}) =>
      YoutubeLocalPlaylist(
        id: id,
        name: name ?? this.name,
        videos: videos ?? this.videos,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videos': [for (final v in videos) v.toJson()],
      };

  factory YoutubeLocalPlaylist.fromJson(Map<String, dynamic> j) =>
      YoutubeLocalPlaylist(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        videos: [
          for (final v in (j['videos'] as List? ?? const []).whereType<Map>())
            YoutubeVideo.fromJson(Map<String, dynamic>.from(v)),
        ],
      );
}

import 'youtube_chapter.dart';
import 'youtube_video.dart';

/// Everything the watch page shows around the player.
class YoutubeWatchDetails {
  final String id;
  final String title;
  final String viewsLabel; // e.g. "23,268,087 views"
  final String dateLabel; // e.g. "Nov 10, 2014"
  final String channelName;
  final String? channelId;
  final String? channelAvatarUrl;
  final String subscribersLabel; // e.g. "1.23M subscribers"
  final String description;
  final List<YoutubeVideo> related;

  /// Token for fetching this video's comments, carried on the watch page.
  final String? commentsToken;

  /// Chapters, when the video has them. Empty is the common case.
  final List<YoutubeChapter> chapters;

  const YoutubeWatchDetails({
    required this.id,
    required this.title,
    this.viewsLabel = '',
    this.dateLabel = '',
    this.channelName = '',
    this.channelId,
    this.channelAvatarUrl,
    this.subscribersLabel = '',
    this.description = '',
    this.related = const [],
    this.commentsToken,
    this.chapters = const [],
  });

  String get url => 'https://www.youtube.com/watch?v=$id';
}

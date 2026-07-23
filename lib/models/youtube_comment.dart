/// A top-level comment on a video.
class YoutubeComment {
  final String id;
  final String author; // "@handle"
  final String? channelId;
  final String avatarUrl;
  final String text;
  final String publishedLabel; // e.g. "3 years ago"
  final bool isCreator; // posted by the video's channel
  final bool isVerified;
  final String likeLabel; // e.g. "1.2K"; empty when none
  final int replyCount;

  /// Continuation token to fetch this comment's reply thread, or null if none.
  final String? replyToken;

  const YoutubeComment({
    required this.id,
    required this.author,
    required this.text,
    this.channelId,
    this.avatarUrl = '',
    this.publishedLabel = '',
    this.isCreator = false,
    this.isVerified = false,
    this.likeLabel = '',
    this.replyCount = 0,
    this.replyToken,
  });
}

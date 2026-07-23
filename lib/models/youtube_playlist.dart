/// A playlist as it appears in search results.
class YoutubePlaylist {
  final String id;
  final String title;
  final String thumbnailUrl;

  /// The channel that owns it, when the listing says.
  final String author;

  /// e.g. "142 videos". Free text, because YouTube's own label is.
  final String videoCountLabel;

  const YoutubePlaylist({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    this.author = '',
    this.videoCountLabel = '',
  });
}

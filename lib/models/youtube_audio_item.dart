/// One track in the background YouTube-audio queue: just what's needed to play
/// the audio and show it on the now-playing surfaces (mini-player, OS media
/// controls). The actual audio stream URL is resolved lazily each time the track
/// is opened, so an expired URL is never reused.
class YoutubeAudioItem {
  final String videoId;
  final String title;
  final String author; // channel name
  final String thumbnailUrl;
  final Duration? duration;

  const YoutubeAudioItem({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.duration,
  });
}

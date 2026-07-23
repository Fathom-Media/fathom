/// A chapter within a YouTube video.
class YoutubeChapter {
  final String title;
  final Duration start;

  const YoutubeChapter({required this.title, required this.start});

  String get startLabel {
    final h = start.inHours;
    final mm = (start.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = (start.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// Thumbnail sizes YouTube serves for the same still.
///
/// Roughly 3KB, 10KB, 21KB and 65KB for default / mq / hq / maxres. On a grid
/// of 40 results that's the difference between ~120KB and ~2.6MB, which is why
/// NewPipe makes it a setting.
enum YtThumbQuality { low, medium, high, max }

YtThumbQuality thumbQualityFrom(String? name) => switch (name) {
      'low' => YtThumbQuality.low,
      'medium' => YtThumbQuality.medium,
      'max' => YtThumbQuality.max,
      _ => YtThumbQuality.high,
    };

const _files = {
  YtThumbQuality.low: 'default',
  YtThumbQuality.medium: 'mqdefault',
  YtThumbQuality.high: 'hqdefault',
  YtThumbQuality.max: 'maxresdefault',
};

/// Every size YouTube's own URLs use, so any of them can be recognised and
/// swapped. `oar2` appears on Shorts.
final _known = RegExp(
    r'/(default|mqdefault|hqdefault|sddefault|maxresdefault|hq720|oar2)\.jpg');

/// Rewrites a YouTube thumbnail URL to [quality].
///
/// The signed query parameters (sqp/rs) are tied to the size YouTube picked,
/// but they're optional — the bare URL serves the same image, verified against
/// i.ytimg.com for every size. So the parameters are dropped rather than
/// carried onto a size they don't describe.
///
/// Anything that isn't a recognisable i.ytimg still is returned untouched:
/// channel avatars and playlist covers live elsewhere and must not be mangled.
String youtubeThumbnail(String url, YtThumbQuality quality) {
  if (url.isEmpty) return url;
  if (!url.contains('i.ytimg.com') && !url.contains('/vi/')) return url;
  final match = _known.firstMatch(url);
  if (match == null) return url;

  // maxres doesn't exist for every video, and a 404 shows the error placeholder
  // rather than a smaller image, so the cost of missing is a blank card.
  final file = _files[quality]!;
  final base = url.substring(0, match.start);
  return '$base/$file.jpg';
}

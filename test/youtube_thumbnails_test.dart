import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/services/youtube_thumbnails.dart';

void main() {
  const signed = 'https://i.ytimg.com/vi/abc123/hqdefault.jpg'
      '?sqp=-oaymwEXCOADEI4CSFryq4qpAw&rs=AOn4CLC';

  test('swaps the size and drops the signed params', () {
    // The params describe the size YouTube chose; carrying them onto a
    // different size is meaningless. The bare URL serves the same image.
    expect(youtubeThumbnail(signed, YtThumbQuality.medium),
        'https://i.ytimg.com/vi/abc123/mqdefault.jpg');
    expect(youtubeThumbnail(signed, YtThumbQuality.low),
        'https://i.ytimg.com/vi/abc123/default.jpg');
    expect(youtubeThumbnail(signed, YtThumbQuality.max),
        'https://i.ytimg.com/vi/abc123/maxresdefault.jpg');
  });

  test('recognises every size YouTube actually serves', () {
    for (final f in ['default', 'mqdefault', 'hqdefault', 'sddefault',
                     'maxresdefault', 'hq720', 'oar2']) {
      final url = 'https://i.ytimg.com/vi/abc123/$f.jpg';
      expect(youtubeThumbnail(url, YtThumbQuality.high),
          'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
          reason: '$f should be recognised and swapped');
    }
  });

  test('leaves non-video images alone', () {
    // Channel avatars and playlist covers are not /vi/ stills; rewriting them
    // would break them.
    const avatar = 'https://yt3.ggpht.com/abc=s176-c-k-c0x00ffffff-no-rj';
    expect(youtubeThumbnail(avatar, YtThumbQuality.low), avatar);
    expect(youtubeThumbnail('', YtThumbQuality.low), '');
    expect(youtubeThumbnail('https://example.com/x.jpg', YtThumbQuality.low),
        'https://example.com/x.jpg');
  });

  test('maps stored names, defaulting to high', () {
    expect(thumbQualityFrom('low'), YtThumbQuality.low);
    expect(thumbQualityFrom('max'), YtThumbQuality.max);
    expect(thumbQualityFrom(null), YtThumbQuality.high);
    expect(thumbQualityFrom('nonsense'), YtThumbQuality.high);
  });
}

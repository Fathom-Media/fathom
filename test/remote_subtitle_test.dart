import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/remote_subtitle.dart';

// Results in the shape a real 12.0 server returned for Bullet Train
// (2026-09-15), through the Open Subtitles plugin: 27 of them, all srt, with
// download counts in the hundreds of thousands.
RemoteSubtitle _r(String name,
        {bool hash = false, double? rating, int? downloads}) =>
    RemoteSubtitle.fromJson({
      'Id': 'e02a34f56233e3e5e776-$name',
      'Name': name,
      'ProviderName': 'Open Subtitles',
      'Format': 'srt',
      'IsHashMatch': hash,
      'CommunityRating': rating,
      'DownloadCount': downloads,
      'ThreeLetterISOLanguageName': 'eng',
    });

void main() {
  test('a result keeps what the picker shows', () {
    final r = _r('Bullet.Train.1080p.WEB-DL.DDP5.1.H.264-EVO',
        rating: 10, downloads: 1029528);
    expect(r.name, 'Bullet.Train.1080p.WEB-DL.DDP5.1.H.264-EVO');
    expect(r.providerName, 'Open Subtitles');
    expect(r.format, 'srt');
    expect(r.downloadCount, 1029528);
    expect(r.communityRating, 10);
    expect(r.isHashMatch, isFalse);
    expect(r.id.isNotEmpty, isTrue);
  });

  test('a match on your own file comes first', () {
    // Even against a far more popular one: its timing fits this release.
    final sorted = sortRemoteSubtitles([
      _r('popular', rating: 10, downloads: 1029528),
      _r('exact', hash: true, rating: 6, downloads: 12),
    ]);
    expect(sorted.first.name, 'exact');
  });

  test('then rating, then downloads', () {
    final sorted = sortRemoteSubtitles([
      _r('c', rating: 9.3, downloads: 171370),
      _r('a', rating: 10, downloads: 195310),
      _r('b', rating: 10, downloads: 1029528),
      _r('d'),
    ]);
    expect(sorted.map((r) => r.name), ['b', 'a', 'c', 'd']);
  });

  test('a nameless result still has something to show', () {
    final r = RemoteSubtitle.fromJson({
      'Id': 'x',
      'ProviderName': 'Open Subtitles',
    });
    expect(r.name, 'Open Subtitles');
  });
}

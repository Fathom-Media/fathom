import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/services/youtube_search_params.dart';

/// The encoder has to reproduce YouTube's own published constants exactly. If
/// it doesn't, everything else about it is guesswork.
void main() {
  test('reproduces the known videos-only constant', () {
    expect(YoutubeSearchParams.build(filter: YtSearchFilter.videos),
        'EgIQAQ%3D%3D');
  });

  test('reproduces the known channels and playlists constants', () {
    expect(YoutubeSearchParams.build(filter: YtSearchFilter.channels),
        'EgIQAg%3D%3D');
    expect(YoutubeSearchParams.build(filter: YtSearchFilter.playlists),
        'EgIQAw%3D%3D');
  });

  test('reproduces sort-by-upload-date + videos (CAISAhAB)', () {
    // 08 02 12 02 10 01 — outer{1:sort=2, 2:filters{2:type=1}}
    expect(
      YoutubeSearchParams.build(
          filter: YtSearchFilter.videos, sort: YtSearchSort.uploadDate),
      'CAISAhAB',
    );
  });

  test('relevance is omitted, being protobuf default 0', () {
    // Sorting by relevance must produce the plain videos-only constant, not a
    // longer one with an explicit zero.
    expect(
      YoutubeSearchParams.build(
          filter: YtSearchFilter.videos, sort: YtSearchSort.relevance),
      YoutubeSearchParams.build(filter: YtSearchFilter.videos),
    );
  });

  test('upload date and duration combine into the filters message', () {
    final p = YoutubeSearchParams.build(
      filter: YtSearchFilter.videos,
      uploadDate: YtUploadDate.thisWeek,
      duration: YtDuration.over20Min,
    );
    // filters{1:upload=3, 2:type=1, 3:duration=2} = 08 03 10 01 18 02 (len 6)
    expect(p, 'EgYIAxABGAI%3D');
  });

  test('duration is dropped for non-video searches', () {
    // A channel has no length; sending one makes a nonsense query.
    expect(
      YoutubeSearchParams.build(
          filter: YtSearchFilter.channels, duration: YtDuration.over20Min),
      YoutubeSearchParams.build(filter: YtSearchFilter.channels),
    );
  });

  test('every combination encodes without throwing', () {
    for (final f in YtSearchFilter.values) {
      for (final s in YtSearchSort.values) {
        for (final u in YtUploadDate.values) {
          for (final d in YtDuration.values) {
            expect(
                YoutubeSearchParams.build(
                    filter: f, sort: s, uploadDate: u, duration: d),
                isNotEmpty);
          }
        }
      }
    }
  });
}

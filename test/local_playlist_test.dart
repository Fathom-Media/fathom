import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/models/youtube_local_playlist.dart';
import 'package:fathom/models/youtube_video.dart';

YoutubeVideo v(String id) => YoutubeVideo(
      id: id,
      title: 'Title $id',
      author: 'Someone',
      url: 'https://www.youtube.com/watch?v=$id',
      thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      duration: const Duration(minutes: 3, seconds: 5),
      viewCount: 1234,
    );

void main() {
  test('a playlist survives a round-trip through storage', () {
    final before = YoutubeLocalPlaylist(
      id: 'pl_1',
      name: 'Late Night',
      videos: [v('a'), v('b')],
    );
    final after = YoutubeLocalPlaylist.fromJson(before.toJson());

    expect(after.id, before.id);
    expect(after.name, before.name);
    expect(after.videos.map((e) => e.id), ['a', 'b']);
    // The fields the row renders have to come back, or a saved playlist shows
    // blank titles and no duration until something refetches it.
    expect(after.videos.first.title, 'Title a');
    expect(after.videos.first.duration, const Duration(minutes: 3, seconds: 5));
    expect(after.videos.first.thumbnailUrl, isNotEmpty);
    expect(after.videos.first.viewCount, 1234);
    expect(after.videos.first.url, contains('watch?v=a'));
  });

  test('a live stream (null duration) round-trips as live, not as zero', () {
    final live = YoutubeVideo(
      id: 'x',
      title: 'Live',
      author: 'Someone',
      url: 'u',
      thumbnailUrl: 't',
    );
    final back = YoutubeVideo.fromJson(live.toJson());
    expect(back.duration, isNull);
    expect(back.isLive, isTrue);
    expect(back.durationLabel, 'LIVE');
  });

  test('contains and countLabel', () {
    final p = YoutubeLocalPlaylist(id: 'p', name: 'n', videos: [v('a')]);
    expect(p.contains('a'), isTrue);
    expect(p.contains('zz'), isFalse);
    expect(p.countLabel, '1 video');
    expect(p.copyWith(videos: [v('a'), v('b')]).countLabel, '2 videos');
  });

  test('thumbnail falls back to empty rather than throwing when empty', () {
    const p = YoutubeLocalPlaylist(id: 'p', name: 'n');
    expect(p.thumbnailUrl, '');
    expect(p.countLabel, '0 videos');
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/youtube_video.dart';
import 'package:fathom/state/youtube_providers.dart';

YoutubeVideo v(String id) => YoutubeVideo(
      id: id,
      title: 'Video $id',
      author: 'Someone',
      url: 'https://www.youtube.com/watch?v=$id',
      thumbnailUrl: 't',
    );

void main() {
  late ProviderContainer c;
  YoutubeQueue queue() => c.read(youtubeQueueProvider.notifier);
  List<String> ids() => c.read(youtubeQueueProvider).map((e) => e.id).toList();

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('add appends; play next jumps the queue', () {
    queue().add(v('a'));
    queue().add(v('b'));
    expect(ids(), ['a', 'b']);
    queue().playNext(v('c'));
    expect(ids(), ['c', 'a', 'b']);
  });

  test('adding something already queued does not duplicate it', () {
    queue().add(v('a'));
    queue().add(v('a'));
    expect(ids(), ['a']);
  });

  test('play next on a queued video moves it rather than duplicating', () {
    queue().add(v('a'));
    queue().add(v('b'));
    queue().playNext(v('b'));
    expect(ids(), ['b', 'a']);
  });

  test('takeNext pops in order and empties out', () {
    queue().add(v('a'));
    queue().add(v('b'));
    expect(queue().takeNext()?.id, 'a');
    expect(ids(), ['b']);
    expect(queue().takeNext()?.id, 'b');
    expect(queue().takeNext(), isNull, reason: 'empty queue returns null');
    expect(ids(), isEmpty);
  });

  test('reorder moves an item to the target index', () {
    queue().add(v('a'));
    queue().add(v('b'));
    queue().add(v('c'));
    queue().reorder(0, 2);
    expect(ids(), ['b', 'c', 'a']);
  });

  test('remove and clear', () {
    queue().add(v('a'));
    queue().add(v('b'));
    queue().remove('a');
    expect(ids(), ['b']);
    queue().clear();
    expect(ids(), isEmpty);
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/widgets/youtube_actions.dart';

void main() {
  test('builds a canonical watch URL', () {
    expect(YoutubeActions.urlFor('dQw4w9WgXcQ'),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  });

  test('the row menu and the card menu are the same menu', () {
    // A card and a row are the same video. If each built its own menu they
    // would drift, and which actions you get would depend on the list-mode
    // setting — which is exactly the sort of gap nobody reports.
    final row = File('lib/widgets/youtube_cards.dart').readAsStringSync();
    final card =
        File('lib/widgets/youtube_video_collection.dart').readAsStringSync();
    for (final src in [row, card]) {
      expect(src.contains('YoutubeActions.menuItems'), isTrue);
      // No hand-rolled duplicates of the same entries.
      expect(src.contains("Text('Add to Queue')"), isFalse,
          reason: 'menu entries belong in YoutubeActions, not inlined');
    }
  });

  test('right-click and long-press both open the menu, on rows and cards', () {
    for (final p in [
      'lib/widgets/youtube_cards.dart',
      'lib/widgets/youtube_video_collection.dart',
    ]) {
      final src = File(p).readAsStringSync();
      expect(src.contains('onSecondaryTapUp'), isTrue,
          reason: '$p should support right-click');
      expect(src.contains('onLongPressStart'), isTrue,
          reason: '$p should support long-press');
    }
  });
}

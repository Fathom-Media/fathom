import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/screens/discover_screen.dart';

void main() {
  group('orderedSeerrRows', () {
    const known = [
      'recentlyAdded',
      'recentRequests',
      'trending',
      'popularMovies',
    ];

    test('empty order falls back to the known set, in order', () {
      expect(
        orderedSeerrRows(const [], const [], known: known),
        known,
      );
    });

    test('respects a saved order', () {
      expect(
        orderedSeerrRows(
          const ['trending', 'recentlyAdded'],
          const [],
          known: known,
        ),
        // saved first, then any remaining known rows appended
        ['trending', 'recentlyAdded', 'recentRequests', 'popularMovies'],
      );
    });

    test('drops unknown ids from a stale saved order', () {
      expect(
        orderedSeerrRows(
          const ['goneSection', 'trending'],
          const [],
          known: known,
        ),
        ['trending', 'recentlyAdded', 'recentRequests', 'popularMovies'],
      );
    });

    test('appends known rows missing from the saved order', () {
      // A build adds a new row: it should appear even if not in saved order.
      expect(
        orderedSeerrRows(
          const ['recentlyAdded'],
          const [],
          known: known,
        ),
        ['recentlyAdded', 'recentRequests', 'trending', 'popularMovies'],
      );
    });

    test('hides rows in the hidden set', () {
      expect(
        orderedSeerrRows(
          const [],
          const ['recentRequests', 'popularMovies'],
          known: known,
        ),
        ['recentlyAdded', 'trending'],
      );
    });

    test('de-duplicates a repeated id in the saved order', () {
      expect(
        orderedSeerrRows(
          const ['trending', 'trending', 'recentlyAdded'],
          const [],
          known: known,
        ),
        ['trending', 'recentlyAdded', 'recentRequests', 'popularMovies'],
      );
    });
  });
}

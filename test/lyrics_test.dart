import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/models/lyrics.dart';

void main() {
  test('parses synced lyrics with tick timestamps', () {
    // Jellyfin ticks are 100ns: 10,000,000 ticks = 1 second.
    final l = SongLyrics.fromJson({
      'Metadata': {'IsSynced': true},
      'Lyrics': [
        {'Text': 'First line', 'Start': 0},
        {'Text': 'Second line', 'Start': 12000000},
        {'Text': 'Third line', 'Start': 25500000},
      ],
    });
    expect(l.isSynced, isTrue);
    expect(l.lines, hasLength(3));
    expect(l.lines[0].start, Duration.zero);
    expect(l.lines[1].start, const Duration(milliseconds: 1200));
    expect(l.lines[2].start, const Duration(milliseconds: 2550));
  });

  test('a Start of 0 is a real line, not "no timing"', () {
    final l = SongLyrics.fromJson({
      'Metadata': {'IsSynced': true},
      'Lyrics': [
        {'Text': 'Intro at zero', 'Start': 0},
        {'Text': 'Later', 'Start': 30000000},
      ],
    });
    expect(l.isSynced, isTrue, reason: 'a first line at t=0 is still timed');
    expect(l.lines.first.start, Duration.zero);
  });

  test('plain lyrics with no timing are not treated as synced', () {
    final l = SongLyrics.fromJson({
      'Metadata': {'IsSynced': false},
      'Lyrics': [
        {'Text': 'Just the words'},
        {'Text': 'no timestamps'},
      ],
    });
    expect(l.isSynced, isFalse);
    expect(l.lines, hasLength(2));
    expect(l.lines.first.start, isNull);
  });

  test('the server saying synced is overruled when a line lacks timing', () {
    // Trust the data, not the flag: one untimed line means it can't follow
    // along, and highlighting would jump wrong.
    final l = SongLyrics.fromJson({
      'Metadata': {'IsSynced': true},
      'Lyrics': [
        {'Text': 'Timed', 'Start': 1000000},
        {'Text': 'Untimed'},
      ],
    });
    expect(l.isSynced, isFalse,
        reason: 'a missing timestamp breaks sync regardless of the flag');
  });

  test('empty lyrics', () {
    final l = SongLyrics.fromJson({'Metadata': {}, 'Lyrics': []});
    expect(l.isEmpty, isTrue);
    expect(l.isSynced, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/models/lyrics.dart';

void main() {
  test('parses LrcLib synced output', () {
    // The exact shape LrcLib returns.
    const lrc = '[00:19.67] We\'re no strangers to love\n'
        '[00:23.31] You know the rules and so do I\n'
        '[00:27.75] A full commitment\'s what I\'m thinking of';
    final l = parseLrc(lrc);
    expect(l.isSynced, isTrue);
    expect(l.lines, hasLength(3));
    expect(l.lines[0].start, const Duration(seconds: 19, milliseconds: 670));
    expect(l.lines[0].text, "We're no strangers to love");
    expect(l.lines[1].start, const Duration(seconds: 23, milliseconds: 310));
  });

  test('centiseconds vs milliseconds fractions', () {
    // [mm:ss.xx] is centiseconds; [mm:ss.xxx] is milliseconds.
    expect(parseLrc('[01:05.50] a').lines.first.start,
        const Duration(minutes: 1, seconds: 5, milliseconds: 500));
    expect(parseLrc('[01:05.500] a').lines.first.start,
        const Duration(minutes: 1, seconds: 5, milliseconds: 500));
  });

  test('a line with no fraction still parses', () {
    expect(parseLrc('[00:30] line').lines.first.start,
        const Duration(seconds: 30));
  });

  test('one line repeated at several times becomes several timed lines', () {
    // A repeated chorus line carries multiple timestamps.
    final l = parseLrc('[00:10.00][01:20.00][02:30.00] Chorus');
    expect(l.lines, hasLength(3));
    expect(l.lines.map((e) => e.text).toSet(), {'Chorus'});
    // And they come out in order regardless of tag order.
    expect(l.lines[0].start! < l.lines[1].start!, isTrue);
    expect(l.lines[1].start! < l.lines[2].start!, isTrue);
  });

  test('metadata tags are skipped, not shown as lyrics', () {
    final l = parseLrc('[ar:Rick Astley]\n[length:03:33]\n[00:19.67] Real line');
    expect(l.lines, hasLength(1));
    expect(l.lines.first.text, 'Real line');
  });

  test('plain lyrics with no timestamps parse as unsynced', () {
    final l = parseLrc('First line\nSecond line\nThird line');
    expect(l.isSynced, isFalse);
    expect(l.lines, hasLength(3));
    expect(l.lines.first.start, isNull);
  });
}

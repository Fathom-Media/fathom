import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/models/lyrics.dart';
import 'package:fathom/widgets/lyrics_view.dart';

void main() {
  const lines = [
    LyricLine(text: 'one', start: Duration.zero),
    LyricLine(text: 'two', start: Duration(seconds: 10)),
    LyricLine(text: 'three', start: Duration(seconds: 20)),
  ];

  test('before the first line, nothing is active', () {
    expect(activeLyricLine(lines, const Duration(seconds: -1)), -1);
  });
  test('at t=0 the first line is active, not "before"', () {
    expect(activeLyricLine(lines, Duration.zero), 0);
  });
  test('exactly on a start counts as that line', () {
    expect(activeLyricLine(lines, const Duration(seconds: 10)), 1);
  });
  test('between two lines stays on the earlier one', () {
    expect(activeLyricLine(lines, const Duration(seconds: 15)), 1);
  });
  test('past the last line stays on the last', () {
    expect(activeLyricLine(lines, const Duration(minutes: 5)), 2);
  });
  test('empty lyrics never crash', () {
    expect(activeLyricLine(const [], const Duration(seconds: 5)), -1);
  });
}

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the pattern in youtube_watch_screen.dart. Timestamps in descriptions
/// are how creators index a long video, but the text around them is arbitrary,
/// so the pattern has to be picky about what it turns into a link.
final pattern = RegExp(r'(?<![\d:])(\d{1,2}:)?\d{1,2}:\d{2}(?![\d:])');

Duration? parse(String s) {
  final parts = s.split(':').map(int.tryParse).toList();
  if (parts.any((p) => p == null)) return null;
  return switch (parts.length) {
    2 => Duration(minutes: parts[0]!, seconds: parts[1]!),
    3 => Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!),
    _ => null,
  };
}

List<String> matches(String s) =>
    pattern.allMatches(s).map((m) => m.group(0)!).toList();

void main() {
  test('finds the shapes creators actually write', () {
    expect(matches('0:00 Intro\n1:23 Middle\n01:02:03 End'),
        ['0:00', '1:23', '01:02:03']);
  });

  test('parses to the right duration', () {
    expect(parse('1:23'), const Duration(minutes: 1, seconds: 23));
    expect(parse('01:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(parse('0:00'), Duration.zero);
  });

  test('does not match inside a longer digit run', () {
    // The lookarounds exist for this: "1234:56" is not a timestamp, and
    // matching ':56' or '34:56' inside it would produce a bogus seek link.
    expect(matches('1234:56'), isEmpty);
    expect(matches('12:34:56:78'), isEmpty);
  });

  test('ignores prose that merely contains a colon', () {
    expect(matches('Note: this is fine'), isEmpty);
    expect(matches('Ratio 16:9 aspect'), isEmpty,
        reason: '16:9 has one digit after the colon, not two');
  });

  test('a timestamp mid-sentence still matches', () {
    expect(matches('skip to 4:15 for the good bit'), ['4:15']);
  });

  test('matches at a line start and a line end', () {
    expect(matches('2:00'), ['2:00']);
    expect(matches('chapter\n3:30'), ['3:30']);
  });
}

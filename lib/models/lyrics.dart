import 'dart:convert';

/// One line of a song's lyrics.
class LyricLine {
  final String text;

  /// When the line starts. Null on unsynced lyrics (a plain text block, no
  /// timing), which is a real and common case — plenty of songs only have the
  /// words, not the timing.
  final Duration? start;

  const LyricLine({required this.text, this.start});
}

/// A song's lyrics, timed if the source provided timing.
class SongLyrics {
  final List<LyricLine> lines;

  /// True when every line carries a start time, so the view can follow along
  /// and highlight the current line. False falls back to a plain, scrollable
  /// block.
  final bool isSynced;

  const SongLyrics({this.lines = const [], this.isSynced = false});

  bool get isEmpty => lines.isEmpty;

  factory SongLyrics.fromJson(Map<String, dynamic> j) {
    final raw = (j['Lyrics'] as List? ?? const []).whereType<Map>();
    final lines = <LyricLine>[];
    for (final e in raw) {
      final text = '${e['Text'] ?? ''}';
      final ticks = (e['Start'] as num?)?.toInt();
      lines.add(LyricLine(
        text: text,
        // Jellyfin ticks are 100ns, as everywhere else in the API: 10 ticks to
        // a microsecond. A Start of 0 is a genuine first line at t=0, so it is
        // NOT treated as "no timing".
        start: ticks == null ? null : Duration(microseconds: ticks ~/ 10),
      ));
    }
    // The server flags this, but it can disagree with reality, so trust the
    // data: synced only if every line actually has a time to sync to.
    final metaSays =
        (j['Metadata'] as Map?)?['IsSynced'] == true;
    final everyLineTimed =
        lines.isNotEmpty && lines.every((l) => l.start != null);
    return SongLyrics(lines: lines, isSynced: metaSays && everyLineTimed);
  }
}

/// Parses an LRC document, the `[mm:ss.xx] text` format LrcLib and most lyric
/// sources return.
///
/// Handles the parts that actually appear in the wild: two- or three-digit
/// fractions, multiple timestamps on one line (a repeated chorus line), and
/// metadata tags like [ar:] and [length:] which are skipped. Lines with no
/// timestamp become untimed lines, so a plain-text block still parses.
SongLyrics parseLrc(String lrc) {
  final timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];
  var anyTimed = false;

  for (final raw in const LineSplitter().convert(lrc)) {
    final matches = timeTag.allMatches(raw).toList();
    // The words are whatever's left once the timestamps are stripped.
    final text = raw.replaceAll(timeTag, '').trim();

    if (matches.isEmpty) {
      // A metadata tag like [ar:Artist] has brackets but no time; drop those,
      // keep genuine untimed lyric text.
      if (RegExp(r'^\[[a-z]+:').hasMatch(raw.trim())) continue;
      if (text.isNotEmpty) lines.add(LyricLine(text: text));
      continue;
    }

    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final frac = m.group(3);
      // "50" is centiseconds, "500" is milliseconds: scale by width.
      final ms = frac == null
          ? 0
          : (int.parse(frac) * (frac.length == 2 ? 10 : 1));
      anyTimed = true;
      lines.add(LyricLine(
        text: text,
        start: Duration(minutes: min, seconds: sec, milliseconds: ms),
      ));
    }
  }

  // Multiple timestamps produce out-of-order lines; sort the timed ones.
  if (anyTimed) {
    lines.sort((a, b) {
      final x = a.start, y = b.start;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
  }
  final everyTimed = lines.isNotEmpty && lines.every((l) => l.start != null);
  return SongLyrics(lines: lines, isSynced: anyTimed && everyTimed);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../models/lyrics.dart';

/// Lyrics that follow the song.
///
/// Synced lyrics highlight the current line and scroll to keep it centred, and
/// tapping a line seeks to it. Unsynced lyrics — just the words, no timing — are
/// a plain scrollable block, which is a common and legitimate case rather than
/// a degraded one.
/// The last line whose start is at or before [position], or -1 before the first.
///
/// Top-level and pure so the off-by-one this "last at or before" scan invites is
/// tested directly, without spinning up a Player.
int activeLyricLine(List<LyricLine> lines, Duration position) {
  var found = -1;
  for (var i = 0; i < lines.length; i++) {
    final start = lines[i].start;
    if (start != null && start <= position) {
      found = i;
    } else {
      break;
    }
  }
  return found;
}

class LyricsView extends StatefulWidget {
  final SongLyrics lyrics;
  final Player player;

  const LyricsView({super.key, required this.lyrics, required this.player});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  StreamSubscription<Duration>? _sub;
  int _active = -1;

  /// Suppresses auto-scroll for a moment after the user scrolls by hand, so
  /// reading ahead doesn't get yanked back to the current line every tick.
  DateTime? _userScrolledAt;

  @override
  void initState() {
    super.initState();
    if (widget.lyrics.isSynced) {
      _sub = widget.player.stream.position.listen(_onPosition);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  int _lineAt(Duration position) => activeLyricLine(widget.lyrics.lines, position);

  void _onPosition(Duration position) {
    final line = _lineAt(position);
    if (line == _active) return;
    setState(() => _active = line);

    // Don't fight a reader who just scrolled up to look ahead.
    final since = _userScrolledAt;
    if (since != null &&
        DateTime.now().difference(since) < const Duration(seconds: 4)) {
      return;
    }
    _centre(line);
  }

  void _centre(int line) {
    if (!_scroll.hasClients || line < 0) return;
    // Each line is roughly one row tall; centre it in the viewport. Estimated
    // rather than measured, which is close enough for a smooth follow and far
    // simpler than per-line keys.
    const rowHeight = 52.0;
    final target = (line * rowHeight) -
        (_scroll.position.viewportDimension / 2) +
        (rowHeight / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = widget.lyrics.lines;
    final synced = widget.lyrics.isSynced;

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          final active = synced && i == _active;
          // Blank lines are spacer beats in an .lrc; keep the gap, drop the row.
          if (line.text.trim().isEmpty) return const SizedBox(height: 18);

          final row = AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: theme.textTheme.titleMedium!.copyWith(
              height: 1.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: active
                  ? scheme.primary
                  : (synced
                      // Passed lines dim; upcoming ones are readable but quiet.
                      ? scheme.onSurface.withValues(
                          alpha: (_active >= 0 && i < _active) ? 0.4 : 0.7)
                      : scheme.onSurface.withValues(alpha: 0.85)),
            ),
            child: Text(line.text, textAlign: TextAlign.center),
          );

          if (!synced || line.start == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: row,
            );
          }
          // Tapping a timed line jumps there — lyrics double as a fine-grained
          // seek bar, which is half the reason to show them.
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => widget.player.seek(line.start!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: row,
            ),
          );
        },
      ),
    );
  }
}

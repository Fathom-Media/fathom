import 'dart:collection';
import 'dart:io';

/// A lightweight in-memory ring buffer of diagnostic log lines plus a report
/// builder. When the user turns on Diagnostic logging (Settings > Playback >
/// Advanced), the player creates a verbose libmpv logger and feeds its lines
/// here, and records a line each time playback opens. The user can then copy
/// the whole report into a bug report, so playback/streaming issues can be read
/// from a real log instead of guessed from a description.
///
/// Nothing captured here carries credentials: stream URLs are passed through
/// [redactUrl] first, and callers pass already-safe header values.
class Diagnostics {
  Diagnostics._();
  static final Diagnostics instance = Diagnostics._();

  static const int _max = 3000;
  final Queue<String> _lines = Queue<String>();

  /// Mirrors the `diagnosticLogging` pref, kept in sync by the app once prefs
  /// load. Capture is app-wide (global error hooks, app logs, verbose mpv), but
  /// [add] is a no-op until this is on, so nothing is recorded unless the user
  /// has opted in. The player also checks it before wiring a verbose logger
  /// (which has a real cost).
  bool enabled = false;

  /// Append a line. No-ops unless [enabled], so global callers (error hooks,
  /// a teed debugPrint) can call unconditionally without leaking data or cost
  /// when diagnostics are off.
  void add(String source, String message) {
    if (!enabled) return;
    final line = '${DateTime.now().toIso8601String()} [$source] $message';
    _lines.add(line);
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
  }

  bool get isEmpty => _lines.isEmpty;
  int get length => _lines.length;

  void clear() => _lines.clear();

  /// Build a shareable text report: an environment header, the caller-supplied
  /// [header] entries (app version, active server version, relevant prefs),
  /// then the captured log lines.
  String report(Map<String, Object?> header) {
    final b = StringBuffer();
    b.writeln('=== Fathom diagnostics ===');
    b.writeln('Captured: ${DateTime.now().toIso8601String()}');
    b.writeln(
        'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    header.forEach((k, v) => b.writeln('$k: $v'));
    b.writeln('');
    b.writeln('--- Log (${_lines.length} lines) ---');
    for (final l in _lines) {
      b.writeln(l);
    }
    return b.toString();
  }
}

/// Strip credentials from a URL's query (api_key / token / password) before it
/// goes into a log the user may share. Leaves everything else intact so the
/// stream path, container, and transcode params stay readable.
String redactUrl(String url) {
  try {
    final u = Uri.parse(url);
    if (u.queryParameters.isEmpty) return url;
    final safe = <String, String>{};
    for (final e in u.queryParameters.entries) {
      final k = e.key.toLowerCase();
      final secret =
          k.contains('key') || k.contains('token') || k.contains('pass');
      safe[e.key] = secret ? '<redacted>' : e.value;
    }
    return u.replace(queryParameters: safe).toString();
  } catch (_) {
    return url;
  }
}

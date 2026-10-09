import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that the app speaks with one voice. These are source checks, not
/// widget tests: the point is that a new screen can't quietly reintroduce a
/// one-off style that looks almost, but not quite, like everything else.
Iterable<File> _sources() sync* {
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is File &&
        f.path.endsWith('.dart') &&
        !f.path.contains('/generated/')) {
      yield f;
    }
  }
}

List<String> _hits(RegExp pattern, {required String except}) {
  final found = <String>[];
  for (final f in _sources()) {
    if (f.path.endsWith(except)) continue;
    final src = f.readAsStringSync();
    for (final m in pattern.allMatches(src)) {
      final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      found.add('${f.path}:$line');
    }
  }
  return found;
}

void main() {
  test('feedback goes through the one app snackbar', () {
    // showSnack/showSnackOn (widgets/app_snack.dart) carry the icon, the tone,
    // the duration and the clear-the-previous-one behaviour. A raw SnackBar is
    // a plain grey bar with none of that, sitting at a different height.
    final raw = _hits(
      RegExp(r'\bSnackBar\('),
      except: 'widgets/app_snack.dart',
    );
    expect(
      raw,
      isEmpty,
      reason:
          'Use showSnack()/showSnackOn() instead of a raw SnackBar:\n'
          '${raw.join('\n')}',
    );
  });

  test('spinners come from the shared AppSpinner', () {
    // Loose CircularProgressIndicators drift in stroke width and size, and
    // without a fixed box they resize with whatever is around them.
    final raw = _hits(
      RegExp(r'\bCircularProgressIndicator\('),
      except: 'widgets/app_spinner.dart',
    );
    expect(
      raw,
      isEmpty,
      reason:
          'Use AppSpinner instead of a bare CircularProgressIndicator:\n'
          '${raw.join('\n')}',
    );
  });

  test('the Jellyfin client is never held as dynamic', () {
    // Its methods live in extensions, one per API area, and an extension
    // method called on a dynamic value doesn't exist at runtime: it throws
    // NoSuchMethodError. Three places did this after the split, and the catch
    // around them hid it. Playback never told the server it had started, so
    // no resume point was ever saved, and the admin user and server settings
    // editors couldn't load or save.
    final untyped = _hits(
      RegExp(r'\bdynamic\s+client\b'),
      except: '(no exceptions)',
    );
    expect(
      untyped,
      isEmpty,
      reason: 'Type it as JellyfinClient:\n${untyped.join('\n')}',
    );
  });

  test('the volume button is never aligned inside a shrinking row', () {
    // A FittedBox sizes to its child, so an Align(centerRight) in a Stack
    // there collapses to the button's own width and lands on top of Play.
    // The layout that works everywhere is the button as the last item in the
    // row, floating, with an equal gap reserved on the left.
    final aligned = _hits(
        RegExp(r'Align\(\s*alignment: Alignment\.centerRight,'
            r'\s*child: VerticalVolumeButton'),
        except: '(no exceptions)');
    expect(aligned, isEmpty,
        reason: 'Put VerticalVolumeButton(floating: true) in the row instead:'
            '\n${aligned.join('\n')}');
  });

  test('the old per-user Jellyfin routes are only ever a fallback', () {
    // Jellyfin 12 dropped the whole /Users/{userId}/... family from its API
    // (checked against a 12.1 server's own spec): /Items?userId= replaces
    // /Users/{id}/Items, /UserViews replaces /Users/{id}/Views, and so on. The
    // old ones still answer today, so nothing breaks, but they can go at any
    // release. They belong only in a fallback for older servers.
    // Only the routes 12 actually dropped: /Users/{id} itself and its Policy
    // are still part of the API.
    final gone = RegExp(r'\$baseUrl/Users/\$userId/'
        r'(Views|Items|PlayedItems|FavoriteItems|Password|Images)');
    final offenders = <String>[];
    for (final f in _sources()) {
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!gone.hasMatch(lines[i])) continue;
        final context = lines.sublist(i < 8 ? 0 : i - 8, i + 1).join('\n');
        final isFallback = context.contains('legacyUrl') ||
            context.contains('on DioException') ||
            context.contains('older servers');
        if (!isFallback) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Call the documented route and pass this one as legacyUrl:\n'
            '${offenders.join('\n')}');
  });

  test('version examples in the docs match the current release', () {
    // Example file names and version strings in the README, roadmap, and docs
    // site go stale quietly after a release. Bumping pubspec's minor version
    // fails this until they are refreshed along with the rest of the docs.
    final minor = RegExp(r'^version: 0\.(\d+)\.', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1);
    final version = RegExp(r'(?<![\d.])0\.(\d+)\.\d+');
    final pages = [
      File('README.md'),
      File('ROADMAP.md'),
      for (final f in Directory('docs').listSync(recursive: true))
        if (f is File && f.path.endsWith('.md')) f,
    ];
    final stale = <String>[];
    for (final f in pages) {
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in version.allMatches(lines[i])) {
          if (m.group(1) != minor) stale.add('${f.path}:${i + 1} ${m[0]}');
        }
      }
    }
    expect(stale, isEmpty,
        reason: 'Refresh these for 0.$minor and check the pages around them '
            'for other outdated details:\n${stale.join('\n')}');
  });
}

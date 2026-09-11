import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that the app speaks with one voice. These are source checks, not
/// widget tests: the point is that a new screen can't quietly reintroduce a
/// one-off style that looks almost, but not quite, like everything else.
Iterable<File> _sources() sync* {
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart') && !f.path.contains('/generated/')) {
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
    final raw = _hits(RegExp(r'\bSnackBar\('), except: 'widgets/app_snack.dart');
    expect(raw, isEmpty,
        reason: 'Use showSnack()/showSnackOn() instead of a raw SnackBar:\n'
            '${raw.join('\n')}');
  });

  test('spinners come from the shared AppSpinner', () {
    // Loose CircularProgressIndicators drift in stroke width and size, and
    // without a fixed box they resize with whatever is around them.
    final raw = _hits(RegExp(r'\bCircularProgressIndicator\('),
        except: 'widgets/app_spinner.dart');
    expect(raw, isEmpty,
        reason: 'Use AppSpinner instead of a bare CircularProgressIndicator:\n'
            '${raw.join('\n')}');
  });
}

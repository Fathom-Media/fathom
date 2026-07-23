@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every YouTube setting must actually do something.
///
/// A setting that renders, persists, and is read by nothing looks identical to
/// a working one from the settings screen — you toggle it and nothing happens.
/// This finds them: each `youtube*` field on Prefs has to be read somewhere
/// that isn't the model itself or the settings screen that draws it.
void main() {
  test('no YouTube setting is declared and then never used', () {
    final prefsSrc = File('lib/state/preferences.dart').readAsStringSync();

    // Fields on Prefs, e.g. "final bool youtubeShowComments;"
    final fields = RegExp(r'final [\w<>?, ]+ (youtube\w+);')
        .allMatches(prefsSrc)
        .map((m) => m.group(1)!)
        .toSet();
    expect(fields, isNotEmpty, reason: 'the regex should find the fields');

    // Everywhere that isn't the declaration or the settings UI.
    final consumers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            !f.path.endsWith('state/preferences.dart') &&
            !f.path.endsWith('screens/preferences_screen.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final dead = <String>[
      for (final f in fields)
        if (!RegExp(r'\b' + f + r'\b').hasMatch(consumers)) f,
    ]..sort();

    expect(dead, isEmpty,
        reason: 'these settings are shown and stored but nothing reads them, '
            'so toggling them does nothing:\n  ${dead.join('\n  ')}');
  });
}

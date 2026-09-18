import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/state/preferences.dart';

// Volume levelling is stored per account like the rest of the player settings,
// so it survives a restart and rides along in a settings backup.
void main() {
  test('volume levelling is off until asked for', () {
    const p = Prefs();
    expect(p.replayGain, 'off');
    expect(p.replayGainFallback, 0);
  });

  test('the choice round-trips through storage', () {
    const p = Prefs();
    final saved = p
        .copyWith(replayGain: 'album', replayGainFallback: -3.5)
        .toJson();
    final back = Prefs.fromJson(saved);
    expect(back.replayGain, 'album');
    expect(back.replayGainFallback, -3.5);
  });

  test('an older saved file without the keys reads as off', () {
    final back = Prefs.fromJson(const {'volume': 80.0});
    expect(back.replayGain, 'off');
    expect(back.replayGainFallback, 0);
  });
}

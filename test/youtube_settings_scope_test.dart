@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/state/preferences.dart';

/// The YouTube settings must stay YouTube's.
///
/// The player controls are shared between the Jellyfin player and the YouTube
/// player, so a YouTube setting read inside the shared widget — or inside the
/// Jellyfin screen — silently changes Jellyfin playback too. The names all
/// carry a youtube prefix precisely so this is greppable.
void main() {
  final youtubeOnly = RegExp(
      r'\b(youtubeSeek\w+|youtubeKeep\w+|youtubeShow\w+|youtubeContent\w+|'
      r'youtubeConfirm\w+|youtubeResume\w+|youtubeQuality)\b');

  test('the Jellyfin player reads no YouTube settings', () {
    final src = File('lib/screens/player_screen.dart').readAsStringSync();
    expect(youtubeOnly.allMatches(src).map((m) => m.group(0)).toSet(), isEmpty,
        reason: 'the Jellyfin player must not depend on YouTube settings');
  });

  test('the shared player controls read no settings at all', () {
    // It takes values as parameters instead, so each caller decides.
    final src = File('lib/widgets/player_controls.dart').readAsStringSync();
    expect(youtubeOnly.allMatches(src).map((m) => m.group(0)).toSet(), isEmpty);
    expect(src.contains('preferencesProvider'), isFalse,
        reason: 'the shared controls must not read prefs directly');
  });

  test('the shared controls default to the standard 10/30', () {
    // Jellyfin passes nothing, so the defaults are its behaviour.
    const p = Prefs();
    expect(p.youtubeSeekBackSeconds, 10);
    expect(p.youtubeSeekForwardSeconds, 30);
  });

  test('new YouTube settings survive a round-trip', () {
    const p = Prefs(
      youtubeContentLanguage: 'de',
      youtubeContentCountry: 'DE',
      youtubeSeekBackSeconds: 15,
      youtubeSeekForwardSeconds: 60,
      youtubeKeepWatchHistory: false,
      youtubeKeepSearchHistory: false,
      youtubeResumePlayback: false,
      youtubeShowComments: false,
      youtubeShowRelated: false,
      youtubeShowDescription: false,
      youtubeConfirmClearQueue: false,
    );
    final back = Prefs.fromJson(p.toJson());
    expect(back.youtubeContentLanguage, 'de');
    expect(back.youtubeContentCountry, 'DE');
    expect(back.youtubeSeekBackSeconds, 15);
    expect(back.youtubeSeekForwardSeconds, 60);
    expect(back.youtubeKeepWatchHistory, isFalse);
    expect(back.youtubeKeepSearchHistory, isFalse);
    expect(back.youtubeResumePlayback, isFalse);
    expect(back.youtubeShowComments, isFalse);
    expect(back.youtubeShowRelated, isFalse);
    expect(back.youtubeShowDescription, isFalse);
    expect(back.youtubeConfirmClearQueue, isFalse);
  });

  test('defaults keep existing behaviour for anyone upgrading', () {
    // An existing install has none of these keys stored. Reading an empty map
    // must not silently turn history off or change how the player seeks.
    final fresh = Prefs.fromJson(const {});
    expect(fresh.youtubeKeepWatchHistory, isTrue);
    expect(fresh.youtubeKeepSearchHistory, isTrue);
    expect(fresh.youtubeResumePlayback, isTrue);
    expect(fresh.youtubeShowComments, isTrue);
    expect(fresh.youtubeShowRelated, isTrue);
    expect(fresh.youtubeShowDescription, isTrue);
    expect(fresh.youtubeSeekBackSeconds, 10);
    expect(fresh.youtubeSeekForwardSeconds, 30);
    expect(fresh.youtubeContentLanguage, 'en');
    expect(fresh.youtubeContentCountry, 'US');
  });
}

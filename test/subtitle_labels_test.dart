import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/services/subtitle_labels.dart';

// Bullet Train as a real server reports it (2026-09-15): seventeen subtitle
// tracks, most of them picture-based, several pairs identical but for their
// position in the file. The picker showed "en" three times and "zh" three
// times, because it used the player's language code and nothing else.
SubtitleStream _s(int index, String display,
        {String? title,
        bool text = false,
        bool forced = false,
        bool external = false,
        String codec = 'PGSSUB'}) =>
    SubtitleStream(
      index: index,
      isExternal: external,
      isTextSubtitleStream: text,
      displayTitle: display,
      title: title,
      isForced: forced,
      codec: codec,
    );

final _bulletTrain = [
  _s(3, 'English - Default - Forced - SUBRIP',
      text: true, forced: true, codec: 'subrip'),
  _s(4, 'English - PGSSUB'),
  _s(5, 'English - PGSSUB'),
  _s(6, 'For commentary - English - PGSSUB', title: 'For commentary'),
  _s(7, 'Chinese - PGSSUB'),
  _s(8, 'Chinese - PGSSUB'),
];

void main() {
  late AppLocalizations l;
  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('a track is named from what the server knows', () {
    final labels = [
      for (final s in _bulletTrain)
        serverSubtitleLabel(l, s),
    ];
    expect(labels, [
      'English (Forced, SRT)',
      'English (Picture, PGS)',
      'English (Picture, PGS)',
      'For commentary (Picture, PGS)',
      'Chinese (Picture, PGS)',
      'Chinese (Picture, PGS)',
    ]);
  });

  test('a track in its own file says so', () {
    final label = serverSubtitleLabel(
        l, _s(20, 'English - SUBRIP', text: true, external: true, codec: 'subrip'));
    expect(label, 'English (External, SRT)');
  });

  test('repeats are numbered so they can be told apart', () {
    final labels = numberRepeats([
      for (final s in _bulletTrain) serverSubtitleLabel(l, s),
    ]);
    expect(labels, [
      'English (Forced, SRT)',
      'English (Picture, PGS) 1',
      'English (Picture, PGS) 2',
      'For commentary (Picture, PGS)',
      'Chinese (Picture, PGS) 1',
      'Chinese (Picture, PGS) 2',
    ]);
  });

  test('picture formats are the ones the app cannot draw', () {
    for (final codec in ['PGSSUB', 'hdmv_pgs_subtitle', 'dvd_subtitle',
        'dvdsub', 'dvb_subtitle', 'vobsub', 'XSUB']) {
      expect(isImageSubtitleCodec(codec), isTrue, reason: codec);
    }
    for (final codec in ['subrip', 'ass', 'mov_text', 'webvtt', 'ssa', null]) {
      expect(isImageSubtitleCodec(codec), isFalse, reason: '$codec');
    }
  });

  // Bullet Train's audio, as the same server reports it: a 5.1 DTS-HD master
  // track and a stereo commentary. The picker showed "en" and a bare title.
  test('an audio track says its format and layout', () {
    expect(
      serverAudioLabel(
          l,
          const AudioStream(
            index: 1,
            codec: 'dts',
            profile: 'DTS-HD MA',
            displayTitle: 'English - DTS-HD MA - 5.1 - Default',
            language: 'eng',
            channelLayout: '5.1',
            channels: 6,
            isDefault: true,
          )),
      'English (DTS-HD MA 5.1)',
    );
    expect(
      serverAudioLabel(
          l,
          const AudioStream(
            index: 2,
            codec: 'aac',
            profile: 'LC',
            title: 'Commentary by David Leitch/Kelly McCormick/Zak Olkewicz',
            displayTitle:
                'Commentary by David Leitch/Kelly McCormick/Zak Olkewicz - English - AAC - Stereo',
            language: 'eng',
            channelLayout: 'stereo',
            channels: 2,
          )),
      'Commentary by David Leitch/Kelly McCormick/Zak Olkewicz (AAC Stereo)',
    );
  });

  test('the layout falls back to the channel count', () {
    expect(serverAudioLabel(l, const AudioStream(index: 1, codec: 'eac3', channels: 8, language: 'eng')),
        'eng (EAC3 7.1)');
    expect(serverAudioLabel(l, const AudioStream(index: 1, codec: 'aac', channels: 1, language: 'eng')),
        'eng (AAC Mono)');
  });

  test('a format with no common name is left off', () {
    expect(subtitleFormatName('subrip'), 'SRT');
    expect(subtitleFormatName('PGSSUB'), 'PGS');
    expect(subtitleFormatName('dvdsub'), 'VobSub');
    expect(subtitleFormatName('something_new'), isNull);
    expect(
        serverSubtitleLabel(
            l,
            const SubtitleStream(
                index: 1,
                isExternal: false,
                isTextSubtitleStream: true,
                displayTitle: 'English - SOMETHING',
                codec: 'something_new')),
        'English');
  });
}


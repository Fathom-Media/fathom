@Tags(['live'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/services/youtube_innertube.dart';
import 'package:fathom/services/lrclib.dart';
import 'package:fathom/services/sponsorblock.dart';
import 'package:fathom/services/youtube_search_params.dart';
import 'package:fathom/services/youtube_streams.dart';

/// Hits the real endpoint. Not part of the default suite.
void main() {
  final yt = YoutubeInnerTube(dio: Dio());
  final l = lookupAppLocalizations(const Locale('en'));

  test('channel search parses', () async {
    final page = await yt.search('johnny carson', filter: YtSearchFilter.channels);
    expect(page.channels, isNotEmpty);
    final c = page.channels.first;
    // ignore: avoid_print
    print('CHANNEL id=${c.id}\n  title=${c.title}\n  subs=${c.subscribersLabel}\n'
        '  handle=${c.handle}\n  logo=${c.logoUrl}');
    expect(c.id, startsWith('UC'));
    expect(c.title, isNotEmpty);
    expect(c.logoUrl, startsWith('https://'));
    expect(c.subscribersLabel.toLowerCase(), contains('subscriber'));
  });

  test('playlist search parses', () async {
    final page = await yt.search('johnny carson', filter: YtSearchFilter.playlists);
    expect(page.playlists, isNotEmpty);
    final p = page.playlists.first;
    // ignore: avoid_print
    print('PLAYLIST id=${p.id}\n  title=${p.title}\n  author=${p.author}\n'
        '  count=${p.videoCountLabel}\n  thumb=${p.thumbnailUrl}');
    expect(p.id, isNotEmpty);
    expect(p.title, isNotEmpty);
    expect(p.thumbnailUrl, startsWith('https://'));
  });

  test('video search still parses', () async {
    final page = await yt.search('johnny carson');
    expect(page.videos, isNotEmpty);
    // ignore: avoid_print
    print('VIDEOS parsed=${page.videos.length} first="${page.videos.first.title}"');
  });

  test('captions dedupe to one track per language, as real WebVTT', () async {
    final caps = await resolveYoutubeCaptions('dQw4w9WgXcQ');
    expect(caps, isNotEmpty);

    // YouTube lists each language once per format (srv1/srv2/srv3/ttml/vtt),
    // so the raw manifest has ~30 entries for ~6 languages. One per language.
    final codes = caps.map((c) => c.code).toList();
    expect(codes.toSet().length, codes.length,
        reason: 'one track per language, not one per format');

    final en = caps.firstWhere((c) => c.code == 'en');
    expect(en.vttUrl, contains('fmt=vtt'));

    // The default response is YouTube's XML, which mpv cannot parse. Prove the
    // URL we hand mpv actually returns WebVTT.
    final res = await Dio().get<String>(en.vttUrl);
    expect(res.data, startsWith('WEBVTT'));

    // ignore: avoid_print
    print('CAPTIONS langs=${caps.length} first="${caps.first.displayLabel}"');
  });

  test('a video with no captions yields an empty list, not a throw', () async {
    // Playback must never depend on captions existing.
    final caps = await resolveYoutubeCaptions('not-a-real-id-xxxx');
    expect(caps, isEmpty);
  });

  test('chapters parse, and the heatmap is not mistaken for them', () async {
    final d = await yt.watch('8aGhZQkoFbQ');
    expect(d.chapters, isNotEmpty);

    // The response also carries MARKER_TYPE_HEATMAP: ~100 evenly spaced,
    // untitled markers for the "most replayed" graph. Picking that list instead
    // gives a hundred nameless chapters.
    expect(d.chapters.length, lessThan(30));
    expect(d.chapters.every((c) => c.title.isNotEmpty), isTrue);

    // In order, and starting at or near zero.
    for (var i = 1; i < d.chapters.length; i++) {
      expect(d.chapters[i].start, greaterThan(d.chapters[i - 1].start));
    }
    // ignore: avoid_print
    print('CHAPTERS n=${d.chapters.length} '
        'first="${d.chapters.first.title}"@${d.chapters.first.startLabel} '
        'last="${d.chapters.last.title}"@${d.chapters.last.startLabel}');
  });

  test('a video without chapters yields an empty list', () async {
    final d = await yt.watch('dQw4w9WgXcQ');
    expect(d.chapters, isEmpty);
  });

  test('sort and duration filters really change the results', () async {
    // The encoder matching YouTube's constants proves the bytes are right; this
    // proves the server acts on them.
    final relevance = await yt.search('flutter tutorial');
    final newest = await yt.search('flutter tutorial',
        sort: YtSearchSort.uploadDate);
    expect(relevance.videos, isNotEmpty);
    expect(newest.videos, isNotEmpty);
    expect(newest.videos.map((v) => v.id).toList(),
        isNot(equals(relevance.videos.map((v) => v.id).toList())),
        reason: 'sorting by upload date should not return the same order');

    final long = await yt.search('flutter tutorial',
        duration: YtDuration.over20Min);
    expect(long.videos, isNotEmpty);
    final durations =
        long.videos.where((v) => v.duration != null).map((v) => v.duration!);
    // ignore: avoid_print
    print('FILTERS long-only: ${durations.length} timed results, '
        'shortest=${durations.isEmpty ? "-" : durations.reduce((a, b) => a < b ? a : b)}');
    expect(durations.every((d) => d.inMinutes >= 20), isTrue,
        reason: 'the >20min filter must actually exclude short videos');
  });

  test('channel playlists tab returns playlists, not videos', () async {
    final tab = await yt.channelTab(
        'UC7McHNOsrUL2fRxTB_xvgRQ', YtChannelTabKind.playlists);
    expect(tab.isRequestedTab, isTrue);
    expect(tab.playlists, isNotEmpty);
    expect(tab.videos, isEmpty);
    // ignore: avoid_print
    print('TAB playlists n=${tab.playlists.length} '
        'first="${tab.playlists.first.title}" tabs=${tab.availableTabs}');
  });

  test('channel videos tab returns videos', () async {
    final tab = await yt.channelTab(
        'UC7McHNOsrUL2fRxTB_xvgRQ', YtChannelTabKind.videos);
    expect(tab.isRequestedTab, isTrue);
    expect(tab.videos, isNotEmpty);
    // ignore: avoid_print
    print('TAB videos n=${tab.videos.length} first="${tab.videos.first.title}"');
  });

  test('a tab the channel lacks reports itself, rather than passing off Home',
      () async {
    // This channel has no Live tab. YouTube answers with the Home feed and
    // selected tab "Home" — 48 ordinary videos. Rendering those under a Live
    // heading would be a lie, so isRequestedTab must be false and the content
    // dropped.
    final tab = await yt.channelTab(
        'UC7McHNOsrUL2fRxTB_xvgRQ', YtChannelTabKind.live);
    expect(tab.isRequestedTab, isFalse);
    expect(tab.isEmpty, isTrue);
    // ignore: avoid_print
    print('TAB live -> isRequestedTab=${tab.isRequestedTab} '
        'empty=${tab.isEmpty} (channel has no Live tab)');
  });

  test('shorts tab actually returns shorts', () async {
    // This regressed silently: the Shorts tab uses shortsLockupViewModel, not
    // the lockupViewModel everything else uses, so the ordinary reader found
    // nothing and reported an empty tab on a channel with 48 shorts. The tab
    // being *selected* is not evidence that it parsed.
    final tab = await yt.channelTab(
        'UC7McHNOsrUL2fRxTB_xvgRQ', YtChannelTabKind.shorts);
    expect(tab.isRequestedTab, isTrue);
    expect(tab.videos, isNotEmpty, reason: 'this channel has shorts');

    final s = tab.videos.first;
    expect(s.id, isNotEmpty);
    expect(s.title, isNotEmpty);
    expect(s.thumbnailUrl, startsWith('https://'));

    // Shorts carry no duration, and neither do live streams. Without isShort
    // every Short renders with a red LIVE badge.
    expect(s.duration, isNull);
    expect(s.isShort, isTrue);
    expect(s.isLive, isFalse, reason: 'a Short is not a live stream');
    expect(s.durationLabel(l), 'Short');

    // ignore: avoid_print
    print('SHORTS n=${tab.videos.length} first="${s.title}" '
        'views=${s.viewsLabel(l)} label=${s.durationLabel(l)}');
  });

  test('live tab parses on a channel that actually has one', () async {
    // The Johnny Carson channel has no Live tab, so the earlier test proved
    // only that the fallback was rejected — nothing about parsing. NASA
    // streams, so this exercises the real path.
    final tab =
        await yt.channelTab('UCLA_DiR1FfKNvjuUpBHmylQ', YtChannelTabKind.live);
    expect(tab.isRequestedTab, isTrue);
    expect(tab.videos, isNotEmpty);
    expect(tab.videos.first.title, isNotEmpty);
    // ignore: avoid_print
    print('LIVE n=${tab.videos.length} first="${tab.videos.first.title}"');
  });

  test('content language and country change what YouTube returns', () async {
    // hl/gl were hardcoded to en/US, so everyone got American English results
    // wherever they were. This proves the settings reach the wire and that the
    // server acts on them, rather than just that they encode.
    final us = YoutubeInnerTube(language: 'en', country: 'US', dio: Dio());
    final de = YoutubeInnerTube(language: 'de', country: 'DE', dio: Dio());

    final a = await us.search('nachrichten');
    final b = await de.search('nachrichten');
    expect(a.videos, isNotEmpty);
    expect(b.videos, isNotEmpty);
    expect(b.videos.map((v) => v.id).toList(),
        isNot(equals(a.videos.map((v) => v.id).toList())),
        reason: 'a German query from Germany should not match the US results');

    // The clearest tell: YouTube localises its own relative dates.
    final deLabels =
        b.videos.map((v) => v.uploadedLabel ?? '').where((l) => l.isNotEmpty);
    // ignore: avoid_print
    print('LOCALE us-first="${a.videos.first.title}"');
    // ignore: avoid_print
    print('LOCALE de-first="${b.videos.first.title}" '
        'dates=${deLabels.take(2).toList()}');
  });

  test('restricted mode reaches the wire and changes results', () async {
    final normal = YoutubeInnerTube(dio: Dio());
    final safe = YoutubeInnerTube(restrictedMode: true, dio: Dio());
    final a = await normal.search('fight compilation');
    final b = await safe.search('fight compilation');
    expect(a.videos, isNotEmpty);
    expect(b.videos, isNotEmpty);
    final overlap =
        a.videos.map((v) => v.id).toSet().intersection(b.videos.map((v) => v.id).toSet());
    // Filtering is YouTube's, server-side; this proves it acts on the flag
    // rather than that we merely send it.
    expect(overlap.length, lessThan(a.videos.length),
        reason: 'restricted mode should not return an identical result set');
    // ignore: avoid_print
    print('RESTRICTED off=${a.videos.length} on=${b.videos.length} '
        'overlap=${overlap.length}');
  });

  test('sponsorblock returns real segments for a sponsored video', () async {
    final sb = SponsorBlock();
    final segs = await sb.segments('aAOgZ6cjrio',
        categories: {SponsorCategory.sponsor, SponsorCategory.outro});
    expect(segs, isNotEmpty);
    for (final s in segs) {
      expect(s.end, greaterThan(s.start));
      expect(s.uuid, isNotEmpty);
    }
    // ignore: avoid_print
    print('SPONSORBLOCK ${segs.length} segments: '
        '${segs.map((s) => "${s.category.id} ${s.start.inSeconds}-${s.end.inSeconds}s").join(", ")}');
  });

  test('a video with no submissions yields nothing, not an error', () async {
    final segs = await SponsorBlock()
        .segments('dQw4w9WgXcQ', categories: {SponsorCategory.sponsor});
    // The API answers 404 here; it must not surface as a failure.
    expect(segs, isEmpty);
  });

  test('lrclib returns real synced lyrics for a known song', () async {
    final l = await LrcLib().lookup(
      artist: 'Rick Astley',
      title: 'Never Gonna Give You Up',
      album: 'Whenever You Need Somebody',
      duration: const Duration(seconds: 213),
    );
    expect(l, isNotNull);
    expect(l!.isSynced, isTrue);
    expect(l.lines.length, greaterThan(10));
    expect(l.lines.every((line) => line.start != null), isTrue);
    // ignore: avoid_print
    print('LRCLIB ${l.lines.length} lines, first="${l.lines.first.text}" '
        '@${l.lines.first.start!.inSeconds}s');
  });

  test('lrclib returns null for a song it does not have', () async {
    final l = await LrcLib().lookup(
      artist: 'Nonexistent Artist ZZZ',
      title: 'A Song That Does Not Exist QQQ',
      duration: const Duration(seconds: 999),
    );
    expect(l, isNull);
  });
}

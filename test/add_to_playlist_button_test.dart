import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/youtube_local_playlist.dart';
import 'package:fathom/models/youtube_video.dart';
import 'package:fathom/state/youtube_providers.dart';
import 'package:fathom/widgets/add_to_youtube_playlist.dart';

/// Stands in for the real notifier so the test doesn't touch secure storage.
class _FakePlaylists extends YoutubeLocalPlaylists {
  _FakePlaylists(this._initial);
  final List<YoutubeLocalPlaylist> _initial;

  @override
  Future<List<YoutubeLocalPlaylist>> build() async => _initial;
}

final _video = YoutubeVideo(
  id: 'vid1',
  title: 'A video',
  author: 'Someone',
  url: 'https://www.youtube.com/watch?v=vid1',
  thumbnailUrl: 'https://example.invalid/t.jpg',
);

Future<void> pump(WidgetTester tester, List<YoutubeLocalPlaylist> lists) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      youtubeLocalPlaylistsProvider.overrideWith(() => _FakePlaylists(lists)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: AddToPlaylistButton(video: _video)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unsaved video offers Add', (tester) async {
    await pump(tester, [
      const YoutubeLocalPlaylist(id: 'p1', name: 'Later'),
    ]);
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
    expect(find.byTooltip('Add to Playlist'), findsOneWidget);
  });

  testWidgets('a video already in a playlist reads as Saved, not Add',
      (tester) async {
    await pump(tester, [
      YoutubeLocalPlaylist(id: 'p1', name: 'Later', videos: [_video]),
    ]);
    // This is the reported bug: it said Add regardless of being saved.
    expect(find.byIcon(Icons.playlist_add_rounded), findsNothing);
    expect(find.byIcon(Icons.playlist_add_check_rounded), findsOneWidget);
    expect(find.byTooltip('Saved to Playlist'), findsOneWidget);
  });

  testWidgets('saved state tracks the playlist a video is actually in',
      (tester) async {
    await pump(tester, [
      const YoutubeLocalPlaylist(id: 'p1', name: 'Empty'),
      YoutubeLocalPlaylist(
          id: 'p2', name: 'Other', videos: [_video.copyOther()]),
    ]);
    // A different video in a playlist must not mark this one saved.
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
  });
}

extension on YoutubeVideo {
  YoutubeVideo copyOther() => YoutubeVideo(
        id: 'someone-else',
        title: title,
        author: author,
        url: url,
        thumbnailUrl: thumbnailUrl,
      );
}

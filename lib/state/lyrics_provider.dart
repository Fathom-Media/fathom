import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyrics.dart';
import 'providers.dart';
import 'session_controller.dart';
import '../models/base_item.dart';
import '../services/lrclib.dart';
import 'preferences.dart';

/// Lyrics for a track, by item id.
///
/// autoDispose + family: fetched when the now-playing view opens, dropped when
/// it closes, and cached per track so skipping back to a song doesn't refetch.
/// Null means the server has none — a normal, quiet outcome.
final lrcLibProvider = Provider<LrcLib>((ref) => LrcLib());

/// The bits of a track a lyrics lookup needs.
///
/// A value-equal record, not the BaseItemDto, so the family keys stably: the
/// same song rebuilding into a new object doesn't refetch, and the toggle and
/// the view share one request. BaseItemDto has no == override, so keying on it
/// would refetch on every rebuild.
typedef LyricsKey = ({
  String id,
  String title,
  String artist,
  String? album,
  int? durationTicks,
});

LyricsKey lyricsKeyFor(BaseItemDto track) => (
      id: track.id,
      title: track.name,
      artist: track.artistLine ?? track.albumArtist ?? '',
      album: track.album,
      durationTicks: track.runTimeTicks,
    );

/// Lyrics for the track, from the server, or looked up online if it has none.
final lyricsProvider =
    FutureProvider.autoDispose.family<SongLyrics?, LyricsKey>((ref, key) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return null;

  // The server first: embedded .lrc or its own provider plugin, and the only
  // source that reflects lyrics you've deliberately added to your library.
  final own = await ref.read(jellyfinClientProvider).getLyrics(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        itemId: key.id,
      );
  if (own != null && !own.isEmpty) return own;

  // Nothing on the server — look it up, if allowed.
  final lookUp =
      ref.watch(preferencesProvider).asData?.value.lookUpMissingLyrics ?? true;
  if (!lookUp) return own;

  final duration = key.durationTicks == null
      ? null
      : Duration(microseconds: key.durationTicks! ~/ 10);
  return ref.read(lrcLibProvider).lookup(
        artist: key.artist,
        title: key.title,
        album: key.album,
        duration: duration,
      );
});

/// Whether the now-playing view is currently showing lyrics rather than art.
///
/// Session-scoped, not persisted: it's the state of the open screen, defaulting
/// from the showLyricsAutomatically preference. The screen reads that default
/// when it opens; this holds any manual flip after.
final showingLyricsProvider = NotifierProvider<ShowingLyrics, bool?>(
    ShowingLyrics.new);

class ShowingLyrics extends Notifier<bool?> {
  @override
  bool? build() => null; // null = follow the preference until the user decides
  void set(bool v) => state = v;
  void reset() => state = null;
}

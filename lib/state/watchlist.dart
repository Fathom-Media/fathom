import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../models/session.dart';
import 'providers.dart';
import 'session_controller.dart';

/// A single tap, always-there "want to watch" list for things already in your
/// library, distinct from Favorites (which is for what you love, not what's
/// still on your to-do list). Modelled on Netflix's My List: one list per
/// account, newest addition first, and — deliberately, matching Netflix's own
/// behavior — never auto-removed just because you've watched it. You take it
/// off yourself, on purpose.
///
/// Jellyfin has no native "watchlist" field (only IsFavorite), so this is
/// backed by a single hidden Playlist per account, named [kWatchlistName] and
/// resolved by name each time (never a locally-cached id), so it naturally
/// follows whichever account is signed in — exactly like Favorites and
/// Playlists already do — with no extra local storage to keep in sync across
/// devices or a multi-account switch. It's excluded from the regular Playlists
/// screen so it never shows up twice or invites manual mismanagement there.
class WatchlistController extends AsyncNotifier<List<BaseItemDto>> {
  static const kWatchlistName = 'Fathom Watchlist';

  // Cached once resolved so repeated add/remove calls don't re-list every
  // playlist on the server each time; cleared implicitly on session change
  // since a fresh controller instance is created for a new session.
  String? _playlistId;

  @override
  Future<List<BaseItemDto>> build() async {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (session == null) return const [];
    final id = await _findPlaylistId(session);
    _playlistId = id;
    if (id == null) return const [];
    final client = ref.read(jellyfinClientProvider);
    final items = await client.getPlaylistItems(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      playlistId: id,
    );
    // Newest addition first, matching Netflix's My List ordering (Jellyfin
    // appends new entries to the end).
    return items.reversed.toList();
  }

  Future<String?> _findPlaylistId(Session session) async {
    final client = ref.read(jellyfinClientProvider);
    final playlists = await client.getPlaylists(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
    );
    for (final p in playlists) {
      if (p.name == kWatchlistName) return p.id;
    }
    return null;
  }

  /// Finds the hidden playlist, creating it on first-ever use. Never called
  /// just to check status (only when actually adding something), so opening
  /// the Watchlist screen or checking membership never creates an empty
  /// playlist on the server for someone who's never used the feature.
  Future<String> _ensurePlaylistId(Session session) async {
    final existing = _playlistId;
    if (existing != null) return existing;
    final found = await _findPlaylistId(session);
    if (found != null) {
      _playlistId = found;
      return found;
    }
    final client = ref.read(jellyfinClientProvider);
    final created = await client.createPlaylist(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      name: kWatchlistName,
    );
    _playlistId = created;
    return created;
  }

  bool isInWatchlist(String itemId) =>
      (state.asData?.value ?? const []).any((e) => e.id == itemId);

  Future<void> add(BaseItemDto item) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    final playlistId = await _ensurePlaylistId(session);
    await client.addToPlaylist(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      playlistId: playlistId,
      itemIds: [item.id],
    );
    ref.invalidateSelf();
    await future;
  }

  Future<void> remove(String itemId) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final playlistId = _playlistId;
    if (session == null || playlistId == null) return;
    final current = state.asData?.value ?? const [];
    final entry = current.where((e) => e.id == itemId);
    if (entry.isEmpty) return;
    final entryId = entry.first.playlistItemId;
    if (entryId == null) return;
    final client = ref.read(jellyfinClientProvider);
    await client.removeFromPlaylist(
      baseUrl: session.baseUrl,
      token: session.accessToken,
      playlistId: playlistId,
      entryIds: [entryId],
    );
    ref.invalidateSelf();
    await future;
  }
}

final watchlistProvider =
    AsyncNotifierProvider<WatchlistController, List<BaseItemDto>>(
        WatchlistController.new);

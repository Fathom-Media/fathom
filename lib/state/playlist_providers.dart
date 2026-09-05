import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import 'providers.dart';
import 'session_controller.dart';
import 'watchlist.dart';

/// The signed-in user's playlists — excluding the hidden Watchlist playlist
/// ([WatchlistController.kWatchlistName]), which has its own dedicated screen
/// and shouldn't appear twice or invite manual mismanagement here.
final playlistsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final playlists = await client.getPlaylists(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
  return playlists
      .where((p) => p.name != WatchlistController.kWatchlistName)
      .toList();
});

/// The items inside a playlist, in order.
final playlistItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, playlistId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getPlaylistItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    playlistId: playlistId,
  );
});

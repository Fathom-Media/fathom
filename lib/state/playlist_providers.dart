import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import 'providers.dart';
import 'session_controller.dart';

/// The signed-in user's playlists.
final playlistsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getPlaylists(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
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

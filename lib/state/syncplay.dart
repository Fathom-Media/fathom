import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'session_controller.dart';
import 'syncplay_session.dart';

/// Active SyncPlay groups on the server. Capped with a short timeout so a
/// stalled `/SyncPlay/List` surfaces as an inline error fast, instead of leaving
/// the panel on a long spinner that reads like a freeze.
final syncPlayGroupsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getSyncPlayGroups(baseUrl: s.baseUrl, token: s.accessToken)
      .timeout(const Duration(seconds: 8));
});

/// Server users keyed by display name, so a SyncPlay participant (which the
/// server gives us as a name, not an id) can be shown with their real avatar.
final syncPlayUsersProvider =
    FutureProvider.autoDispose<Map<String, Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const {};
  try {
    final users = await ref
        .watch(jellyfinClientProvider)
        .getUsers(baseUrl: s.baseUrl, token: s.accessToken)
        .timeout(const Duration(seconds: 8));
    return {
      for (final u in users)
        if (u['Name'] != null) '${u['Name']}': u,
    };
  } catch (_) {
    return const {};
  }
});

/// Tracks whether we're currently in a SyncPlay ("watch together") group.
class SyncPlayController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> create(String name) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    // Open the socket BEFORE creating, the way jellyfin-web does: the server
    // pushes GroupJoined (and, if the queue is seeded, a PlayQueue) to the
    // session as the New request runs, so the socket must already be listening
    // or we'd miss them. It also avoids a spurious NotInGroup from pinging while
    // the server still considers us groupless.
    state = true;
    await ref.read(syncPlaySessionProvider).connect();
    try {
      await ref
          .read(jellyfinClientProvider)
          .syncPlayNew(baseUrl: s.baseUrl, token: s.accessToken, groupName: name);
    } catch (_) {
      state = false;
      await ref.read(syncPlaySessionProvider).disconnect();
      rethrow;
    }
    ref.invalidate(syncPlayGroupsProvider);
  }

  Future<void> join(String groupId) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    // Socket first (see create): joining an already-playing group, the server
    // sends the current PlayQueue as we join, so we must be listening to follow
    // it to the item.
    state = true;
    await ref.read(syncPlaySessionProvider).connect();
    try {
      await ref.read(jellyfinClientProvider).syncPlayJoin(
          baseUrl: s.baseUrl, token: s.accessToken, groupId: groupId);
    } catch (_) {
      state = false;
      await ref.read(syncPlaySessionProvider).disconnect();
      rethrow;
    }
    ref.invalidate(syncPlayGroupsProvider);
  }

  Future<void> leave() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .syncPlayLeave(baseUrl: s.baseUrl, token: s.accessToken);
    state = false;
    await ref.read(syncPlaySessionProvider).disconnect();
    ref.invalidate(syncPlayGroupsProvider);
  }

  /// Called by the session when the SERVER reports we're no longer in the group
  /// (group ended, we were removed, or the group vanished). Just reflects that
  /// state and tears the socket down; doesn't re-POST Leave.
  void markExited() {
    if (!state) return;
    state = false;
    ref.read(syncPlaySessionProvider).disconnect();
    ref.invalidate(syncPlayGroupsProvider);
  }
}

final syncPlayControllerProvider =
    NotifierProvider<SyncPlayController, bool>(SyncPlayController.new);

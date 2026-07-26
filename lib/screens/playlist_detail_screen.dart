import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/audio_player.dart' show audioControllerProvider;
import '../state/playlist_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_image.dart';
import '../widgets/hover_pill_button.dart';

/// Shows the contents of a playlist with play, reorder-free removal, and
/// delete-playlist actions.
class PlaylistDetailScreen extends ConsumerWidget {
  final BaseItemDto playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  Future<void> _removeEntry(
      BuildContext context, WidgetRef ref, BaseItemDto item) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || item.playlistItemId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).removeFromPlaylist(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            playlistId: playlist.id,
            entryIds: [item.playlistItemId!],
          );
      ref.invalidate(playlistItemsProvider(playlist.id));
      ref.invalidate(playlistsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(l.appRemovedNamed(item.name))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deletePlaylist(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.appDeletePlaylist),
        content: Text(l.appDeletePlaylistConfirm(playlist.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(jellyfinClientProvider).deletePlaylist(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            playlistId: playlist.id,
          );
      ref.invalidate(playlistsProvider);
      if (context.mounted) {
        context.pop();
        messenger.showSnackBar(
            SnackBar(content: Text(l.appDeletedNamed(playlist.name))));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reorder(BuildContext context, WidgetRef ref,
      List<BaseItemDto> items, int oldIndex, int newIndex) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final entryId = items[oldIndex].playlistItemId;
    if (session == null || entryId == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).movePlaylistItem(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            playlistId: playlist.id,
            entryId: entryId,
            newIndex: newIndex,
          );
      ref.invalidate(playlistItemsProvider(playlist.id));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openItem(
      BuildContext context, WidgetRef ref, List<BaseItemDto> items, int i) async {
    final item = items[i];
    if (item.isAudio) {
      await ref.read(audioControllerProvider.notifier).playQueue(items, i);
      if (context.mounted) context.push('/nowplaying');
    } else if (item.isFolder || item.isSeries || item.isAlbum) {
      context.push('/item', extra: item);
    } else {
      context.push('/player', extra: item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(playlistItemsProvider(playlist.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _deletePlaylist(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  title: Text(l.appDeletePlaylist),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: '$e'),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.playlist_add_rounded,
              title: l.appEmptyPlaylist,
              message: l.appEmptyPlaylistMessage,
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    HoverPillButton(
                      icon: Icons.play_arrow_rounded,
                      label: l.commonPlay,
                      primary: true,
                      onTap: () => _openItem(context, ref, items, 0),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      l.appItemsCount(items.length),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(context, ref, items, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return ListTile(
                      key: ValueKey(item.playlistItemId ?? item.id),
                      leading: SizedBox(
                        width: 56,
                        height: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: MediaImage(item: item, landscape: true),
                        ),
                      ),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: item.isEpisode
                          ? Text(item.seriesName ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis)
                          : (item.artistLine != null
                              ? Text(item.artistLine!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        tooltip: l.commonRemove,
                        onPressed: () => _removeEntry(context, ref, item),
                      ),
                      onTap: () => _openItem(context, ref, items, i),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

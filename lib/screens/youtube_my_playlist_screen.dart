import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/youtube_local_playlist.dart';
import '../state/youtube_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/reorder.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/mini_player.dart';
import '../widgets/youtube_cards.dart';
import '../l10n/generated/app_localizations.dart';

/// One of your own playlists: play it, reorder it, take things out of it.
class YoutubeMyPlaylistScreen extends ConsumerWidget {
  final String playlistId;
  const YoutubeMyPlaylistScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final all = ref.watch(youtubeLocalPlaylistsProvider).asData?.value ??
        const <YoutubeLocalPlaylist>[];
    final playlist = all.where((p) => p.id == playlistId).firstOrNull;

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.ytPlaylistFallback)),
        body: EmptyState(
          icon: Icons.playlist_remove_rounded,
          title: l.ytPlaylistNotFound,
        ),
      );
    }

    final notifier = ref.read(youtubeLocalPlaylistsProvider.notifier);
    return Scaffold(
      // Root route outside the shell: dock the background-audio bar so it stays
      // visible here too (collapses when idle, hidden on TV).
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(title: Text(playlist.name)),
      body: playlist.videos.isEmpty
          ? EmptyState(
              icon: Icons.playlist_add_rounded,
              title: l.ytMyPlaylistEmptyTitle,
              message: l.ytMyPlaylistEmptyMessage,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => context.push('/youtube/watch',
                            extra: (
                              videoId: playlist.videos.first.id,
                              title: playlist.videos.first.title,
                            )),
                        style: kInlineButtonStyle,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l.commonPlay),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        playlist.countLabel(l),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    buildDefaultDragHandles: false,
                    itemCount: playlist.videos.length,
                    // onReorderItem, not the deprecated onReorder: it hands
                    // over the index with the lifted item already accounted
                    // for, so no off-by-one adjustment here.
                    onReorderItem: (oldIndex, newIndex) =>
                        notifier.reorder(playlist.id, oldIndex, newIndex),
                    itemBuilder: (context, i) {
                      final v = playlist.videos[i];
                      return dragAnywhere(
                        key: ValueKey('${v.id}-$i'),
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.drag_indicator,
                                  color: dragGripColor(context)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: YoutubeVideoRow(
                                  video: v,
                                  // Already in a playlist: Remove is useful.
                                  showMenu: false,
                                  extraMenuItems: [
                                    ContextMenuAction(
                                      icon: Icons.playlist_remove_rounded,
                                      label: l.ytRemoveFromPlaylist,
                                      onTap: () => notifier.removeVideo(
                                          playlist.id, v.id),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

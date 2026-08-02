import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/youtube_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/youtube_cards.dart';
import '../widgets/youtube_skeletons.dart';
import '../models/youtube_playlist.dart';
import '../l10n/generated/app_localizations.dart';

/// A playlist's videos, in playlist order.
class YoutubePlaylistScreen extends ConsumerWidget {
  final String playlistId;
  final String? title; // shown while the playlist loads

  const YoutubePlaylistScreen({
    super.key,
    required this.playlistId,
    this.title,
  });

  /// Saving keeps a reference, not the contents: the playlist belongs to
  /// someone else and keeps changing, so it's refetched when opened.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final videos = ref.watch(youtubePlaylistProvider(playlistId));
    final saved = ref.watch(youtubeSavedPlaylistsProvider).asData?.value
            .any((p) => p.id == playlistId) ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? l.ytPlaylistFallback),
        actions: [
          IconButton(
            tooltip: saved ? l.ytSaved : l.ytSavePlaylist,
            color: saved ? Theme.of(context).colorScheme.primary : null,
            icon: Icon(saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded),
            onPressed: () => ref
                .read(youtubeSavedPlaylistsProvider.notifier)
                .toggle(YoutubePlaylist(
                  id: playlistId,
                  title: title ?? l.ytPlaylistFallback,
                  thumbnailUrl:
                      videos.asData?.value.firstOrNull?.thumbnailUrl ?? '',
                  author: videos.asData?.value.firstOrNull?.author ?? '',
                )),
          ),
        ],
      ),
      body: videos.when(
        loading: () => const YoutubeVideosSkeleton(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(youtubePlaylistProvider(playlistId)),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.playlist_remove_rounded,
              title: l.ytNothingInPlaylist,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => YoutubeVideoRow(
              video: list[i],
              // Start the playlist from this item: play it and make the rest the
              // up-next queue, so Next/autoplay walk the playlist (NewPipe-style).
              onTap: () {
                ref
                    .read(youtubeQueueProvider.notifier)
                    .playAll(list.sublist(i + 1));
                context.push('/youtube/watch',
                    extra: (videoId: list[i].id, title: list[i].title));
              },
            ),
          );
        },
      ),
    );
  }
}

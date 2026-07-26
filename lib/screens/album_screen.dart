import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/audio_player.dart';
import '../state/library_providers.dart';
import '../widgets/media_image.dart';
import '../widgets/hover_pill_button.dart';

/// Album detail: cover, artist, a play button, and the track list. Rendered by
/// DetailScreen when the item is a MusicAlbum.
class AlbumView extends ConsumerWidget {
  final BaseItemDto album;
  const AlbumView({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tracksAsync = ref.watch(albumTracksProvider(album.id));
    final theme = Theme.of(context);
    final playing = ref.watch(audioControllerProvider).current;
    final shuffleOn =
        ref.watch(audioControllerProvider.select((s) => s.shuffle));
    final tracks = tracksAsync.asData?.value ?? const [];
    final controller = ref.read(audioControllerProvider.notifier);

    Future<void> shufflePlay() async {
      if (tracks.isEmpty) return;
      await controller.playQueue(tracks, 0, shuffle: true);
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text(album.name),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 168,
                      height: 168,
                      child: MediaImage(
                          item: album, placeholderIcon: Icons.album_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(album.name,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      if (album.artistLine != null)
                        Text(album.artistLine!,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(_albumMeta(l, tracks, album.productionYear),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      // Icon pills matching the rest of the app: they expand to
                      // the label on hover (desktop) or press (touch). Wrapped so
                      // they never overflow beside the cover art.
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          HoverPillButton(
                            icon: Icons.play_arrow_rounded,
                            label: l.commonPlay,
                            primary: true,
                            onTap: tracks.isEmpty
                                ? null
                                : () => controller.playQueue(tracks, 0),
                          ),
                          HoverPillButton(
                            icon: Icons.shuffle_rounded,
                            label: l.browseShuffle,
                            // Accent wash while shuffle is on, so the button
                            // reads as an active toggle, not a dead press.
                            tinted: shuffleOn,
                            onTap: tracks.isEmpty ? null : shufflePlay,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        tracksAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$e',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ),
          data: (tracks) => SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final track = tracks[i];
              final isCurrent = playing?.id == track.id;
              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: 28,
                  child: Center(
                    child: isCurrent
                        ? Icon(Icons.equalizer_rounded,
                            color: theme.colorScheme.primary, size: 20)
                        : Text('${track.indexNumber ?? i + 1}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ),
                title: Text(track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isCurrent
                        ? TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)
                        : null),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (track.runTimeTicks != null)
                      Text(_fmtDuration(track.runTimeTicks!),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    PopupMenuButton<String>(
                      tooltip: l.browseMore,
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onSelected: (v) {
                        final c = ref.read(audioControllerProvider.notifier);
                        if (v == 'next') c.playNext(track);
                        if (v == 'queue') c.addToQueue(track);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'next', child: Text(l.browsePlayNext)),
                        PopupMenuItem(
                            value: 'queue', child: Text(l.browseAddToQueue)),
                      ],
                    ),
                  ],
                ),
                onTap: () => ref
                    .read(audioControllerProvider.notifier)
                    .playQueue(tracks, i),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

String _albumMeta(AppLocalizations l, List<BaseItemDto> tracks, int? year) {
  final count = tracks.length;
  final totalMin = tracks.fold<int>(0, (s, t) => s + (t.runTimeTicks ?? 0)) ~/
      600000000; // ticks (100ns) per minute
  return [
    if (year != null) '$year',
    l.browseSongsCount(count),
    if (totalMin > 0) l.browseMinutesShort(totalMin),
  ].join('  ·  ');
}

String _fmtDuration(int ticks) {
  final total = ticks ~/ 10000000;
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'add_to_playlist.dart';
import 'context_menu.dart';
import 'series_download_sheet.dart';

/// Shared per-item context menu (the "hamburger"), the same surface Jellyfin and
/// Fladder expose on a poster, in a detail page, and on an individual episode.
/// Reached off TV by long-press / right-click / a hover hamburger, and on TV by
/// the episode row's visible three-dot stop (grids on TV use the detail
/// overflow instead, keeping the card's D-pad path untouched).
///
/// Presented via [showContextMenu] (a dropdown on a mouse-driven desktop, a
/// bottom sheet on touch/TV), so it always matches every other item menu in
/// the app instead of rolling its own look.
///
/// [at] anchors the desktop dropdown to where the click/tap happened.
/// [fromGrid] adds a "Show Details" row (pointless on a page that already shows
/// them). [onOpenDetails] performs that navigation (usually the card's own tap).
/// [onDeleted] runs after a successful delete (e.g. pop the detail route); when
/// null the caller relies on provider invalidation to refresh a list in place.
Future<void> showItemActionsMenu(
  BuildContext context,
  WidgetRef ref,
  BaseItemDto item, {
  required Offset at,
  bool fromGrid = false,
  VoidCallback? onOpenDetails,
  VoidCallback? onDeleted,
  // Overrides the stored kind for a download (e.g. 'Recording' when the item is
  // reached from the recordings context), so it classifies correctly.
  String? downloadAsType,
}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // The app-wide container, not the caller's `ref`: actions run after the menu
  // closes, and a grid card can be recycled by a scroll (or the route popped)
  // in the meantime, which would make the caller's `ref` throw.
  final container = ProviderScope.containerOf(context, listen: false);
  final cs = Theme.of(context).colorScheme;
  final user = container.read(currentUserProvider).asData?.value;
  final session = container.read(sessionControllerProvider).asData?.value;
  // Mirror the detail overflow's gate exactly (session fallback included) so
  // the same admin sees the same rows from a poster, an episode, or detail.
  final canDelete = (user?.enableContentDeletion ?? false) ||
      (user?.isAdministrator ?? false) ||
      (session?.canDelete ?? false);
  final canRefresh =
      (user?.isAdministrator ?? false) || (session?.isAdmin ?? false);

  final isPlayable = item.isEpisode ||
      item.type == 'Movie' ||
      item.type == 'Video' ||
      item.type == 'MusicVideo' ||
      item.type == 'Audio' ||
      item.type == 'Recording' ||
      item.type == 'TvChannel';
  // Downloadable for offline: a single video (movie/episode/recording), a
  // whole series/season (which queues its episodes), or music: a track, or an
  // album/artist (which queues its tracks). Live channels use their own flow.
  final isDownloadable = item.isEpisode ||
      item.type == 'Movie' ||
      item.type == 'Video' ||
      item.type == 'MusicVideo' ||
      item.type == 'Recording' ||
      item.type == 'Audio' ||
      item.type == 'MusicAlbum' ||
      item.type == 'MusicArtist' ||
      item.isSeries ||
      item.type == 'Season';

  String deleteLabel() {
    if (item.isSeries) return l.actionDeleteSeries;
    if (item.isEpisode) return l.actionDeleteEpisode;
    if (item.type == 'Season') return l.actionDeleteSeason;
    if (item.type == 'Movie') return l.actionDeleteMovie;
    return l.commonDelete;
  }

  final actions = <ContextMenuAction>[];
  if (isPlayable) {
    actions.add(ContextMenuAction(
      icon: item.canResume
          ? Icons.play_circle_outline_rounded
          : Icons.play_arrow_rounded,
      label: item.canResume ? l.detailResume : l.commonPlay,
      onTap: () => context.push('/player', extra: item),
    ));
  }
  if (fromGrid && onOpenDetails != null) {
    actions.add(ContextMenuAction(
      icon: Icons.info_outline_rounded,
      label: l.actionShowDetails,
      onTap: onOpenDetails,
    ));
  }
  actions.add(ContextMenuAction(
    icon: item.userData.played
        ? Icons.check_circle_rounded
        : Icons.check_circle_outline_rounded,
    label: item.userData.played ? l.detailMarkUnwatched : l.detailMarkWatched,
    onTap: () => _mutate(messenger, () async {
      final s = container.read(sessionControllerProvider).asData?.value;
      if (s == null) return;
      await container.read(jellyfinClientProvider).setPlayed(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            itemId: item.id,
            played: !item.userData.played,
          );
      _invalidateLists(container, item);
    }),
  ));
  actions.add(ContextMenuAction(
    icon: item.userData.isFavorite
        ? Icons.favorite_rounded
        : Icons.favorite_border_rounded,
    label:
        item.userData.isFavorite ? l.detailRemoveFavorite : l.detailAddFavorite,
    color: item.userData.isFavorite ? Colors.redAccent : null,
    onTap: () => _mutate(messenger, () async {
      final s = container.read(sessionControllerProvider).asData?.value;
      if (s == null) return;
      await container.read(jellyfinClientProvider).setFavorite(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            itemId: item.id,
            favorite: !item.userData.isFavorite,
          );
      _invalidateLists(container, item);
    }),
  ));
  actions.add(ContextMenuAction(
    icon: Icons.playlist_add_rounded,
    label: l.detailAddToPlaylist,
    onTap: () => showAddToPlaylistSheet(context, ref,
        itemIds: [item.id], label: item.name),
  ));
  if (isDownloadable) {
    final downloads =
        container.read(downloadsProvider).asData?.value ?? const {};
    final isFolder = item.isSeries || item.type == 'Season';
    if (isFolder) {
      // A series offers a scope choice (All / a season); a season is already
      // one scope, so it downloads directly.
      actions.add(ContextMenuAction(
        icon: Icons.download_rounded,
        label: l.detailDownload,
        onTap: () => item.isSeries
            ? showSeriesDownloadSheet(context, item, asType: downloadAsType)
            : container
                .read(downloadsProvider.notifier)
                .download(item, asType: downloadAsType),
      ));
      final hasDownloads = item.isSeries
          ? downloads.values.any((e) => e.seriesId == item.id)
          : downloads.values.any((e) =>
              e.seriesId == item.seriesId &&
              e.seasonNumber == item.indexNumber);
      if (hasDownloads) {
        actions.add(ContextMenuAction(
          icon: Icons.download_done_rounded,
          label: l.detailRemoveDownload,
          onTap: () async {
            final d = container.read(downloadsProvider.notifier);
            if (item.isSeries) {
              await d.deleteSeries(item.id);
            } else {
              await d.deleteSeason(item.seriesId ?? '', item.indexNumber);
            }
          },
        ));
      }
    } else {
      final entry = downloads[item.id];
      if (entry?.status == DownloadStatus.complete) {
        actions.add(ContextMenuAction(
          icon: Icons.download_done_rounded,
          label: l.detailRemoveDownload,
          onTap: () =>
              container.read(downloadsProvider.notifier).delete(item.id),
        ));
      } else if (entry == null || entry.status == DownloadStatus.failed) {
        actions.add(ContextMenuAction(
          icon: Icons.download_rounded,
          label: l.detailDownload,
          onTap: () => container
              .read(downloadsProvider.notifier)
              .download(item, asType: downloadAsType),
        ));
      }
    }
  }
  if (canRefresh) {
    actions.add(ContextMenuAction(
      icon: Icons.refresh_rounded,
      label: l.detailRefreshMetadata,
      onTap: () async {
        final started = l.detailMetadataRefreshStarted;
        await _mutate(messenger, () async {
          final s = container.read(sessionControllerProvider).asData?.value;
          if (s == null) return;
          await container.read(jellyfinClientProvider).refreshItem(
                baseUrl: s.baseUrl,
                token: s.accessToken,
                itemId: item.id,
              );
          messenger.showSnackBar(SnackBar(content: Text(started)));
        });
      },
    ));
  }
  if (canDelete) {
    actions.add(ContextMenuAction(
      icon: Icons.delete_outline_rounded,
      label: deleteLabel(),
      color: cs.error,
      onTap: () =>
          _confirmAndDelete(context, container, messenger, item, onDeleted),
    ));
  }

  await showContextMenu(context, at: at, actions: actions, title: item.name);
}

Future<void> _mutate(
  ScaffoldMessengerState messenger,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _confirmAndDelete(
  BuildContext context,
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  BaseItemDto item,
  VoidCallback? onDeleted,
) async {
  final l = AppLocalizations.of(context);
  final s = container.read(sessionControllerProvider).asData?.value;
  if (s == null) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(l.detailDeleteItem),
      content: Text(l.detailDeleteConfirm(item.name)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(dctx, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dctx, true),
          child: Text(l.commonDelete),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await container.read(jellyfinClientProvider).deleteItem(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          itemId: item.id,
        );
    _invalidateLists(container, item);
    if (item.isEpisode) {
      final sid = item.seriesId;
      if (sid != null) {
        container.invalidate(episodesProvider(sid));
        container.invalidate(nextUpProvider(sid));
      }
    }
    onDeleted?.call();
    messenger.showSnackBar(SnackBar(content: Text(l.detailDeleted(item.name))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

void _invalidateLists(ProviderContainer container, BaseItemDto item) {
  container.invalidate(itemDetailProvider(item.id));
  container.invalidate(resumeItemsProvider);
  container.invalidate(latestItemsProvider);
  container.invalidate(favoriteItemsProvider);
}

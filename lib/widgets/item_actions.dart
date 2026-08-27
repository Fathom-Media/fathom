import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'add_to_playlist.dart';
import 'series_download_sheet.dart';
import 'tv_focus.dart';

/// The actions the shared context menu can return.
enum _ItemAction {
  play,
  showDetails,
  toggleWatched,
  toggleFavorite,
  addToPlaylist,
  download,
  removeDownload,
  refresh,
  delete,
}

/// Shared per-item context menu (the "hamburger"), the same surface Jellyfin and
/// Fladder expose on a poster, in a detail page, and on an individual episode.
/// Reached off TV by long-press / right-click / a hover hamburger, and on TV by
/// the episode row's visible three-dot stop (grids on TV use the detail
/// overflow instead, keeping the card's D-pad path untouched).
///
/// The bottom sheet only PICKS an action and pops with it; the work runs here,
/// after the sheet closes. Data reads/invalidations go through the app-wide
/// [ProviderContainer], not the caller's `ref`, so they survive the caller
/// unmounting mid-request (a grid card recycled by a scroll, a route pop) — and
/// they never touch the sheet's own `ref`, which is gone once it pops.
///
/// [fromGrid] adds a "Show Details" row (pointless on a page that already shows
/// them). [onOpenDetails] performs that navigation (usually the card's own tap).
/// [onDeleted] runs after a successful delete (e.g. pop the detail route); when
/// null the caller relies on provider invalidation to refresh a list in place.
Future<void> showItemActionsMenu(
  BuildContext context,
  WidgetRef ref,
  BaseItemDto item, {
  bool fromGrid = false,
  VoidCallback? onOpenDetails,
  VoidCallback? onDeleted,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final action = await showModalBottomSheet<_ItemAction>(
    context: context,
    useRootNavigator: true,
    showDragHandle: !isTvDevice,
    isScrollControlled: true,
    builder: (ctx) => _ItemActionsSheet(
      item: item,
      showDetailsRow: fromGrid && onOpenDetails != null,
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _ItemAction.play:
      context.push('/player', extra: item);
    case _ItemAction.showDetails:
      onOpenDetails?.call();
    case _ItemAction.addToPlaylist:
      await showAddToPlaylistSheet(context, ref,
          itemIds: [item.id], label: item.name);
    case _ItemAction.download:
      if (item.isSeries) {
        // A series offers a scope choice (All / a season); everything else
        // downloads directly.
        await showSeriesDownloadSheet(context, item);
      } else {
        await container.read(downloadsProvider.notifier).download(item);
      }
    case _ItemAction.removeDownload:
      await container.read(downloadsProvider.notifier).delete(item.id);
    case _ItemAction.toggleWatched:
      await _mutate(messenger, () async {
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
      });
    case _ItemAction.toggleFavorite:
      await _mutate(messenger, () async {
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
      });
    case _ItemAction.refresh:
      final started = AppLocalizations.of(context).detailMetadataRefreshStarted;
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
    case _ItemAction.delete:
      await _confirmAndDelete(context, container, messenger, item, onDeleted);
  }
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

class _ItemActionsSheet extends ConsumerWidget {
  final BaseItemDto item;
  final bool showDetailsRow;

  const _ItemActionsSheet({required this.item, required this.showDetailsRow});

  String _deleteLabel(AppLocalizations l) {
    if (item.isSeries) return l.actionDeleteSeries;
    if (item.isEpisode) return l.actionDeleteEpisode;
    if (item.type == 'Season') return l.actionDeleteSeason;
    if (item.type == 'Movie') return l.actionDeleteMovie;
    return l.commonDelete;
  }

  bool get _isPlayable =>
      item.isEpisode ||
      item.type == 'Movie' ||
      item.type == 'Video' ||
      item.type == 'MusicVideo' ||
      item.type == 'Audio' ||
      item.type == 'Recording' ||
      item.type == 'TvChannel';

  /// Downloadable for offline: a single video (movie/episode) or a whole
  /// series/season (which queues its episodes). Live channels and audio use
  /// their own flows, so they're excluded here.
  bool get _isDownloadable =>
      item.isEpisode ||
      item.type == 'Movie' ||
      item.type == 'Video' ||
      item.type == 'MusicVideo' ||
      item.type == 'Recording' ||
      item.isSeries ||
      item.type == 'Season';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider).asData?.value;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    // Mirror the detail overflow's gate exactly (session fallback included) so
    // the same admin sees the same rows from a poster, an episode, or detail.
    final canDelete = (user?.enableContentDeletion ?? false) ||
        (user?.isAdministrator ?? false) ||
        (session?.canDelete ?? false);
    final canRefresh =
        (user?.isAdministrator ?? false) || (session?.isAdmin ?? false);

    final rows = <Widget>[];
    var first = true;
    void add({
      required IconData icon,
      required String label,
      required _ItemAction action,
      Color? color,
    }) {
      rows.add(_ActionRow(
        icon: icon,
        label: label,
        color: color,
        autofocus: first,
        onTap: () => Navigator.pop(context, action),
      ));
      first = false;
    }

    if (_isPlayable) {
      add(
        icon: item.canResume
            ? Icons.play_circle_outline_rounded
            : Icons.play_arrow_rounded,
        label: item.canResume ? l.detailResume : l.commonPlay,
        action: _ItemAction.play,
      );
    }
    if (showDetailsRow) {
      add(
        icon: Icons.info_outline_rounded,
        label: l.actionShowDetails,
        action: _ItemAction.showDetails,
      );
    }
    add(
      icon: item.userData.played
          ? Icons.check_circle_rounded
          : Icons.check_circle_outline_rounded,
      label: item.userData.played ? l.detailMarkUnwatched : l.detailMarkWatched,
      action: _ItemAction.toggleWatched,
    );
    add(
      icon: item.userData.isFavorite
          ? Icons.favorite_rounded
          : Icons.favorite_border_rounded,
      label:
          item.userData.isFavorite ? l.detailRemoveFavorite : l.detailAddFavorite,
      color: item.userData.isFavorite ? Colors.redAccent : null,
      action: _ItemAction.toggleFavorite,
    );
    add(
      icon: Icons.playlist_add_rounded,
      label: l.detailAddToPlaylist,
      action: _ItemAction.addToPlaylist,
    );
    if (_isDownloadable) {
      // A single item shows its own download state; a series/season is a bulk
      // action (its episodes each track their own state), so it always offers
      // Download.
      final entry = ref.watch(downloadsProvider).asData?.value[item.id];
      final isFolder = item.isSeries || item.type == 'Season';
      if (!isFolder && entry?.status == DownloadStatus.complete) {
        add(
          icon: Icons.download_done_rounded,
          label: l.detailRemoveDownload,
          action: _ItemAction.removeDownload,
        );
      } else if (isFolder || entry == null ||
          entry.status == DownloadStatus.failed) {
        add(
          icon: Icons.download_rounded,
          label: l.detailDownload,
          action: _ItemAction.download,
        );
      }
    }
    if (canRefresh) {
      add(
        icon: Icons.refresh_rounded,
        label: l.detailRefreshMetadata,
        action: _ItemAction.refresh,
      );
    }
    if (canDelete) {
      add(
        icon: Icons.delete_outline_rounded,
        label: _deleteLabel(l),
        color: cs.error,
        action: _ItemAction.delete,
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTvDevice) const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// A single menu row. Off TV it's a normal tappable ListTile; on TV it's a
/// [TvFocusable] driving a non-interactive ListTile, so there's exactly one
/// D-pad stop per row and Select fires reliably (the proven activation path).
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool autofocus;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: color != null ? TextStyle(color: color) : null),
        onTap: onTap,
      );
    }
    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      scale: 1.0,
      borderRadius: BorderRadius.zero,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: color != null ? TextStyle(color: color) : null),
      ),
    );
  }
}

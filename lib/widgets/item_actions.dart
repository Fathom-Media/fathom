import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'add_to_playlist.dart';
import 'tv_focus.dart';

/// Shared per-item context menu (the "hamburger"), the same surface Jellyfin and
/// Fladder expose on a poster, in a detail page, and on an individual episode.
/// Reached off TV by long-press / right-click / a hover hamburger, and on TV by
/// the episode row's visible three-dot stop (grids on TV use the detail
/// overflow instead, keeping the card's D-pad path untouched).
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
}) {
  final tv = isTvDevice;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: !tv,
    isScrollControlled: true,
    builder: (ctx) => _ItemActionsSheet(
      item: item,
      fromGrid: fromGrid,
      onOpenDetails: onOpenDetails,
      onDeleted: onDeleted,
    ),
  );
}

class _ItemActionsSheet extends ConsumerWidget {
  final BaseItemDto item;
  final bool fromGrid;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onDeleted;

  const _ItemActionsSheet({
    required this.item,
    required this.fromGrid,
    required this.onOpenDetails,
    required this.onDeleted,
  });

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider).asData?.value;
    final canDelete =
        (user?.enableContentDeletion ?? false) ||
        (user?.isAdministrator ?? false);
    final canRefresh = user?.isAdministrator ?? false;

    final rows = <Widget>[];
    var first = true;
    Widget row({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? color,
    }) {
      final w = _ActionRow(
        icon: icon,
        label: label,
        color: color,
        autofocus: first,
        onTap: onTap,
      );
      first = false;
      return w;
    }

    // Play / Resume (leaf items only; a container's "play" is ambiguous).
    if (_isPlayable) {
      rows.add(row(
        icon: item.canResume
            ? Icons.play_circle_outline_rounded
            : Icons.play_arrow_rounded,
        label: item.canResume ? l.detailResume : l.commonPlay,
        onTap: () {
          Navigator.pop(context);
          context.push('/player', extra: item);
        },
      ));
    }

    // Show Details (only useful when invoked away from the detail page).
    if (fromGrid && onOpenDetails != null) {
      rows.add(row(
        icon: Icons.info_outline_rounded,
        label: l.actionShowDetails,
        onTap: () {
          Navigator.pop(context);
          onOpenDetails!.call();
        },
      ));
    }

    // Mark watched / unwatched.
    rows.add(row(
      icon: item.userData.played
          ? Icons.check_circle_rounded
          : Icons.check_circle_outline_rounded,
      label: item.userData.played ? l.detailMarkUnwatched : l.detailMarkWatched,
      onTap: () => _run(context, ref, () async {
        final s = ref.read(sessionControllerProvider).asData?.value;
        if (s == null) return;
        await ref.read(jellyfinClientProvider).setPlayed(
              baseUrl: s.baseUrl,
              userId: s.userId,
              token: s.accessToken,
              itemId: item.id,
              played: !item.userData.played,
            );
        _invalidateLists(ref);
      }),
    ));

    // Favorite / unfavorite.
    rows.add(row(
      icon: item.userData.isFavorite
          ? Icons.favorite_rounded
          : Icons.favorite_border_rounded,
      label: item.userData.isFavorite ? l.detailRemoveFavorite : l.detailAddFavorite,
      color: item.userData.isFavorite ? Colors.redAccent : null,
      onTap: () => _run(context, ref, () async {
        final s = ref.read(sessionControllerProvider).asData?.value;
        if (s == null) return;
        await ref.read(jellyfinClientProvider).setFavorite(
              baseUrl: s.baseUrl,
              userId: s.userId,
              token: s.accessToken,
              itemId: item.id,
              favorite: !item.userData.isFavorite,
            );
        _invalidateLists(ref);
      }),
    ));

    // Add to playlist.
    rows.add(row(
      icon: Icons.playlist_add_rounded,
      label: l.detailAddToPlaylist,
      onTap: () {
        Navigator.pop(context);
        showAddToPlaylistSheet(context, ref,
            itemIds: [item.id], label: item.name);
      },
    ));

    // Refresh metadata (admin).
    if (canRefresh) {
      rows.add(row(
        icon: Icons.refresh_rounded,
        label: l.detailRefreshMetadata,
        onTap: () => _run(context, ref, () async {
          final s = ref.read(sessionControllerProvider).asData?.value;
          if (s == null) return;
          await ref.read(jellyfinClientProvider).refreshItem(
                baseUrl: s.baseUrl,
                token: s.accessToken,
                itemId: item.id,
              );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.detailMetadataRefreshStarted)),
            );
          }
        }),
      ));
    }

    // Delete (permission-gated, destructive, always last).
    if (canDelete) {
      rows.add(row(
        icon: Icons.delete_outline_rounded,
        label: _deleteLabel(l),
        color: cs.error,
        onTap: () async {
          Navigator.pop(context);
          await _confirmAndDelete(context, ref);
        },
      ));
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

  /// Close the sheet, run [action], surface any error as a SnackBar.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
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
      await ref.read(jellyfinClientProvider).deleteItem(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            itemId: item.id,
          );
      _invalidateLists(ref);
      if (item.isEpisode) {
        final sid = item.seriesId;
        if (sid != null) {
          ref.invalidate(episodesProvider(sid));
          ref.invalidate(nextUpProvider(sid));
        }
      }
      onDeleted?.call();
      messenger.showSnackBar(
        SnackBar(content: Text(l.detailDeleted(item.name))),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _invalidateLists(WidgetRef ref) {
    ref.invalidate(itemDetailProvider(item.id));
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(latestItemsProvider);
    ref.invalidate(favoriteItemsProvider);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../api/jellyfin_client.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'add_to_playlist.dart';
import 'app_snack.dart';
import 'app_spinner.dart';
import 'ui_common.dart';

/// Which items a grid currently has selected.
///
/// Selection is a mode the grid enters (from a card's own menu, the same way
/// YouTube Downloads does it) rather than a standing affordance, so an ordinary
/// tap keeps opening a title. The chosen items are held whole, not just their
/// ids, because the bulk actions need names for their messages and types to
/// decide what can be deleted.
class ItemSelection extends ChangeNotifier {
  final _items = <String, BaseItemDto>{};

  bool _active = false;
  bool get active => _active;

  Iterable<BaseItemDto> get items => _items.values;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool contains(String id) => _items.containsKey(id);

  void start([BaseItemDto? first]) {
    _active = true;
    if (first != null) _items[first.id] = first;
    notifyListeners();
  }

  void stop() {
    _active = false;
    _items.clear();
    notifyListeners();
  }

  void toggle(BaseItemDto item) {
    if (_items.remove(item.id) == null) _items[item.id] = item;
    notifyListeners();
  }

  void selectAll(Iterable<BaseItemDto> all) {
    for (final i in all) {
      _items[i.id] = i;
    }
    notifyListeners();
  }
}

/// The bar shown above a grid while it's selecting: how many, select-all, and
/// the actions that can run over the whole set.
class SelectionBar extends ConsumerStatefulWidget {
  const SelectionBar({
    super.key,
    required this.selection,
    required this.all,
    this.canDelete = false,
    this.onChanged,
  });

  final ItemSelection selection;

  /// Everything currently on screen, for Select All.
  final List<BaseItemDto> all;

  /// Whether the account may delete media on the server.
  final bool canDelete;

  /// Refreshes whatever the host grid reads from, after a bulk action. Home
  /// rows and item details are invalidated here, but the grid's own source
  /// varies (a paged local list in the library, a different provider per
  /// screen elsewhere), and without this a deleted title stays on screen.
  final VoidCallback? onChanged;

  @override
  ConsumerState<SelectionBar> createState() => _SelectionBarState();
}

class _SelectionBarState extends ConsumerState<SelectionBar> {
  bool _busy = false;

  /// Runs [each] over every selected item and reports once at the end, rather
  /// than a message per item: fifty snackbars for a fifty-item selection is
  /// worse than none.
  Future<void> _bulk(
    Future<void> Function(BaseItemDto item) each,
    String Function(int n) done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final chosen = widget.selection.items.toList();
    setState(() => _busy = true);
    var ok = 0;
    Object? failure;
    for (final item in chosen) {
      try {
        await each(item);
        ok++;
      } catch (e) {
        failure ??= e;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.selection.stop();
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(resumeItemsProvider);
    container.invalidate(latestItemsProvider);
    container.invalidate(favoriteItemsProvider);
    container.invalidate(nextUpItemsProvider);
    for (final item in chosen) {
      container.invalidate(itemDetailProvider(item.id));
    }
    widget.onChanged?.call();
    if (failure != null && ok == 0) {
      showErrorOn(messenger, failure);
    } else {
      showSnackOn(messenger, done(ok), kind: SnackKind.success);
    }
  }

  Future<void> _setPlayed(bool played) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _bulk(
      (item) => client.setPlayed(
        baseUrl: s.baseUrl,
        userId: s.userId,
        token: s.accessToken,
        itemId: item.id,
        played: played,
      ),
      (n) => played ? l.selectionMarkedWatched(n) : l.selectionMarkedUnwatched(n),
    );
  }

  Future<void> _setFavorite(bool favorite) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _bulk(
      (item) => client.setFavorite(
        baseUrl: s.baseUrl,
        userId: s.userId,
        token: s.accessToken,
        itemId: item.id,
        favorite: favorite,
      ),
      (n) => favorite ? l.selectionFavorited(n) : l.selectionUnfavorited(n),
    );
  }

  void _addToPlaylist() {
    final l = AppLocalizations.of(context);
    final ids = [for (final i in widget.selection.items) i.id];
    final label = l.selectionCount(ids.length);
    widget.selection.stop();
    showAddToPlaylistSheet(context, ref, itemIds: ids, label: label);
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final n = widget.selection.length;
    final ok = await confirm(context,
        title: l.selectionDeleteTitle(n),
        message: l.selectionDeleteBody,
        confirmLabel: l.commonDelete,
        destructive: true);
    if (!ok || !mounted) return;
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _bulk(
      (item) => client.deleteItem(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        itemId: item.id,
      ),
      l.selectionDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sel = widget.selection;
    final enabled = !_busy && !sel.isEmpty;
    // Every action as one list, so the wide bar and the narrow overflow menu
    // can't drift apart.
    final actions = <({IconData icon, String label, VoidCallback? run})>[
      (
        icon: Icons.check_circle_outline_rounded,
        label: l.detailMarkWatched,
        run: enabled ? () => _setPlayed(true) : null
      ),
      (
        icon: Icons.remove_done_rounded,
        label: l.detailMarkUnwatched,
        run: enabled ? () => _setPlayed(false) : null
      ),
      (
        icon: Icons.favorite_border_rounded,
        label: l.detailAddFavorite,
        run: enabled ? () => _setFavorite(true) : null
      ),
      (
        icon: Icons.playlist_add_rounded,
        label: l.detailAddToPlaylist,
        run: enabled ? _addToPlaylist : null
      ),
      if (widget.canDelete)
        (
          icon: Icons.delete_outline_rounded,
          label: l.commonDelete,
          run: enabled ? _delete : null
        ),
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: LayoutBuilder(builder: (context, c) {
        // Five icon buttons plus the count and Select All need roughly 600
        // logical pixels; below that they were overflowing the row (measured
        // 250px over at 360 wide), so the actions collapse into one menu.
        final narrow = c.maxWidth < 620;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: l.commonCancel,
                icon: const Icon(Icons.close_rounded),
                onPressed: _busy ? null : sel.stop,
              ),
              Flexible(
                child: Text(l.selectionCount(sel.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: AppSpinner.inline(),
                ),
              if (narrow)
                IconButton(
                  tooltip: l.selectionSelectAll,
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: _busy ? null : () => sel.selectAll(widget.all),
                )
              else
                TextButton(
                  onPressed: _busy ? null : () => sel.selectAll(widget.all),
                  child: Text(l.selectionSelectAll),
                ),
              if (narrow)
                PopupMenuButton<VoidCallback?>(
                  tooltip: l.commonMoreOptions,
                  enabled: enabled,
                  onSelected: (run) => run?.call(),
                  itemBuilder: (context) => [
                    for (final a in actions)
                      PopupMenuItem<VoidCallback?>(
                        value: a.run,
                        enabled: a.run != null,
                        child: Row(
                          children: [
                            Icon(a.icon, size: 20),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(a.label,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              else
                for (final a in actions)
                  IconButton(
                    tooltip: a.label,
                    icon: Icon(a.icon),
                    onPressed: a.run,
                  ),
            ],
          ),
        );
      }),
    );
  }
}

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
  });

  final ItemSelection selection;

  /// Everything currently on screen, for Select All.
  final List<BaseItemDto> all;

  /// Whether the account may delete media on the server.
  final bool canDelete;

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
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: l.commonCancel,
              icon: const Icon(Icons.close_rounded),
              onPressed: _busy ? null : sel.stop,
            ),
            Text(l.selectionCount(sel.length),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: AppSpinner.inline(),
              ),
            TextButton(
              onPressed: _busy ? null : () => sel.selectAll(widget.all),
              child: Text(l.selectionSelectAll),
            ),
            IconButton(
              tooltip: l.detailMarkWatched,
              icon: const Icon(Icons.check_circle_outline_rounded),
              onPressed: enabled ? () => _setPlayed(true) : null,
            ),
            IconButton(
              tooltip: l.detailMarkUnwatched,
              icon: const Icon(Icons.remove_done_rounded),
              onPressed: enabled ? () => _setPlayed(false) : null,
            ),
            IconButton(
              tooltip: l.detailAddFavorite,
              icon: const Icon(Icons.favorite_border_rounded),
              onPressed: enabled ? () => _setFavorite(true) : null,
            ),
            IconButton(
              tooltip: l.detailAddToPlaylist,
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: enabled
                  ? () {
                      final ids = [for (final i in sel.items) i.id];
                      final label = l.selectionCount(ids.length);
                      sel.stop();
                      showAddToPlaylistSheet(context, ref,
                          itemIds: ids, label: label);
                    }
                  : null,
            ),
            if (widget.canDelete)
              IconButton(
                tooltip: l.commonDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: enabled ? _delete : null,
              ),
          ],
        ),
      ),
    );
  }
}

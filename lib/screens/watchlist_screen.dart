import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../state/watchlist.dart';
import '../widgets/item_grid.dart';

/// The user's Watchlist as a poster grid — newest addition first, exactly
/// like Netflix's My List. See [WatchlistController] for why this is distinct
/// from Favorites and how it's stored.
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(watchlistProvider);
    return Scaffold(
      appBar: AppBar(
        leading: mobileDrawerLeading(context),
        title: Text(l.browseWatchlist),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(watchlistProvider),
          ),
        ],
      ),
      body: ItemGridBody(
        items: items,
        emptyIcon: Icons.bookmark_border_rounded,
        emptyTitle: l.browseNoWatchlist,
      ),
    );
  }
}

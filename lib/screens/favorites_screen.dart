import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/library_providers.dart';
import '../widgets/item_grid.dart';

/// The user's favorites as a poster grid.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(favoriteItemsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.browseFavorites),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(favoriteItemsProvider),
          ),
        ],
      ),
      body: ItemGridBody(
        items: items,
        emptyIcon: Icons.favorite_border_rounded,
        emptyTitle: l.browseNoFavorites,
      ),
    );
  }
}

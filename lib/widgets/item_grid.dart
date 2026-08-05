import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../services/tv_mode.dart';
import 'empty_state.dart';
import 'error_view.dart';
import 'media_cards.dart';
import 'motion.dart';
import 'shimmer.dart';

/// Renders a poster grid from an async list, with shimmer/empty/error states.
/// Reused by person filmography, favorites, and collection screens.
class ItemGridBody extends ConsumerWidget {
  final AsyncValue<List<BaseItemDto>> items;
  final String emptyTitle;
  final IconData emptyIcon;

  const ItemGridBody({
    super.key,
    required this.items,
    this.emptyTitle = 'Nothing here',
    this.emptyIcon = Icons.inbox_rounded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return items.when(
      loading: () => const PosterGridSkeleton(),
      error: (e, _) => ErrorView(message: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(icon: emptyIcon, title: emptyTitle);
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          clipBehavior: Clip.none,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 184,
            mainAxisSpacing: 18,
            crossAxisSpacing: 14,
            childAspectRatio: 0.54,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => EntranceFade(
            index: i,
            onceKey: list[i].id,
            child: PosterTile(
              item: list[i],
              // On TV the first tile grabs focus so the remote lands on content.
              autofocus: isTvDevice && i == 0,
              onTap: () => context.push('/item', extra: list[i]),
            ),
          ),
        );
      },
    );
  }
}

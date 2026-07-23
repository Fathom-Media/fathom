import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/preferences.dart';
import 'shimmer.dart';

/// Placeholder while videos load.
///
/// Follows the list/grid setting: a list-shaped skeleton resolving into a grid
/// is a worse first impression than a plain spinner, because it moves the thing
/// you were already looking at.
class YoutubeVideosSkeleton extends ConsumerWidget {
  /// Roughly what fills a screen; more just costs frames nobody sees.
  final int count;
  final EdgeInsets padding;

  const YoutubeVideosSkeleton({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid =
        ref.watch(preferencesProvider).asData?.value.youtubeListMode == 'grid';

    if (grid) {
      return LayoutBuilder(builder: (context, box) {
        final columns = (box.maxWidth / 300).floor().clamp(1, 6);
        return GridView.builder(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 16 / 15.4,
          ),
          itemCount: columns * 2,
          itemBuilder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: ShimmerBox(width: double.infinity)),
              const SizedBox(height: 8),
              const ShimmerBox(height: 14),
              const SizedBox(height: 6),
              ShimmerBox(height: 11, width: box.maxWidth * 0.3),
            ],
          ),
        );
      });
    }

    return ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, i) => const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: 178, height: 100),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(height: 16),
                  SizedBox(height: 8),
                  ShimmerBox(height: 12, width: 160),
                  SizedBox(height: 8),
                  ShimmerBox(height: 12, width: 220),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for the watch page's text while the details load.
///
/// The player is already on screen and playing by this point, so a spinner
/// underneath it says "nothing here yet" about a page that is half-loaded.
class YoutubeWatchSkeleton extends StatelessWidget {
  const YoutubeWatchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(height: 22), // title
          SizedBox(height: 8),
          ShimmerBox(height: 22, width: 260),
          SizedBox(height: 14),
          ShimmerBox(height: 12, width: 180), // views · date
          SizedBox(height: 20),
          Row(children: [
            ShimmerBox(
                width: 40,
                height: 40,
                borderRadius: BorderRadius.all(Radius.circular(20))), // avatar
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(height: 14, width: 140),
                SizedBox(height: 6),
                ShimmerBox(height: 11, width: 90),
              ],
            ),
          ]),
          SizedBox(height: 24),
          ShimmerBox(height: 12),
          SizedBox(height: 8),
          ShimmerBox(height: 12),
          SizedBox(height: 8),
          ShimmerBox(height: 12, width: 240),
        ],
      ),
    );
  }
}

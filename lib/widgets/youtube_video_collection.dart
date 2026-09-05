import 'cached_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/youtube_video.dart';
import '../services/youtube_thumbnails.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import 'context_menu.dart';
import 'tv_focus.dart';
import 'youtube_actions.dart';
import 'youtube_cards.dart';

/// Videos as a list or a grid, following the YouTube list-mode setting.
///
/// One widget rather than the same switch repeated in search, What's New and
/// the channel tabs — they'd drift, and the setting would work in some places
/// and not others.
class YoutubeVideoCollection extends ConsumerWidget {
  final List<YoutubeVideo> videos;

  /// Hidden on channel pages, where the header already says who it is.
  final bool showAuthor;

  /// Appends a loading row/cell for the next page.
  final bool loadingMore;

  final EdgeInsets padding;

  /// Overrides what tapping a video does. Defaults to opening the watch page.
  final void Function(YoutubeVideo)? onTap;

  const YoutubeVideoCollection({
    super.key,
    required this.videos,
    this.showAuthor = true,
    this.loadingMore = false,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(preferencesProvider).asData?.value.youtubeListMode ==
        'grid';
    final count = videos.length + (loadingMore ? 1 : 0);

    if (!grid) {
      return ListView.separated(
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => i >= videos.length
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : YoutubeVideoRow(
                video: videos[i],
                showAuthor: showAuthor,
                onTap: onTap == null ? null : () => onTap!(videos[i]),
              ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      // Cards want roughly 300px; below that the grid is worse than a list.
      final columns = (box.maxWidth / 300).floor().clamp(1, 6);
      return GridView.builder(
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          // 16:9 art plus room for two title lines and a metadata line.
          childAspectRatio: 16 / 15.4,
        ),
        itemCount: count,
        itemBuilder: (_, i) => i >= videos.length
            ? const Center(child: CircularProgressIndicator())
            : YoutubeVideoCard(
                video: videos[i],
                showAuthor: showAuthor,
                onTap: onTap == null ? null : () => onTap!(videos[i]),
              ),
      );
    });
  }
}

/// A video as a card: big 16:9 art with the title underneath.
class YoutubeVideoCard extends ConsumerStatefulWidget {
  final YoutubeVideo video;
  final bool showAuthor;
  final VoidCallback? onTap;

  const YoutubeVideoCard({
    super.key,
    required this.video,
    this.showAuthor = true,
    this.onTap,
  });

  @override
  ConsumerState<YoutubeVideoCard> createState() => _YoutubeVideoCardState();
}

class _YoutubeVideoCardState extends ConsumerState<YoutubeVideoCard> {
  bool _hover = false;

  /// The same menu the list rows have. A card and a row are the same video;
  /// which actions you get must not depend on the layout setting.
  Future<void> _showContextMenu(Offset at) => showContextMenu(
        context,
        at: at,
        actions: YoutubeActions.menuItems(context, ref, widget.video),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = widget.video;
    final quality = thumbQualityFrom(
        ref.watch(preferencesProvider).asData?.value.youtubeThumbnailQuality);
    final meta = [
      if (widget.showAuthor && v.author.isNotEmpty) v.author,
      v.viewsLabel(l),
      v.uploadedText(l, DateTime.now()),
    ].where((s) => s.isNotEmpty).join('  ·  ');

    void effectiveTap() {
      final t = widget.onTap;
      if (t != null) {
        t();
      } else {
        context.push('/youtube/watch', extra: (videoId: v.id, title: v.title));
      }
    }

    final card = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // Opaque so the whole card responds, not only the art and the title.
        behavior: HitTestBehavior.opaque,
        onTap: effectiveTap,
        onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition),
        onLongPressStart: (d) => _showContextMenu(d.globalPosition),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: _hover ? 1.02 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible, not fixed: a card in a grid gets a bounded height,
              // and fixed art plus text overflows the moment the title wraps.
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedImage(
                        url: youtubeThumbnail(v.thumbnailUrl, quality),
                        errorBuilder: (_) => Container(
                          color: scheme.surfaceContainerHigh,
                          child: const Icon(Icons.smart_display_rounded),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: v.isLive ? Colors.red : Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            v.durationLabel(l),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                v.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // On TV, wrap so a D-pad can focus (ring) and Select the card; the hover
    // scale alone is invisible to a remote.
    if (!isTvDevice) return card;
    // On TV, selecting the card opens an action sheet (Play first, then the same
    // actions), since a remote can't reach the mouse-only context menu.
    return TvFocusable(
      onTap: () => YoutubeActions.showTvActionSheet(
        context,
        ref,
        v,
        onPlay: effectiveTap,
      ),
      borderRadius: BorderRadius.circular(12),
      scale: 1.03,
      child: card,
    );
  }
}

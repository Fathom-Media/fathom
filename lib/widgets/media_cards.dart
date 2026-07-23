import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../state/preferences.dart';
import 'media_image.dart';
import 'motion.dart';

/// Poster artwork with a tactile hover: it scales up, gains an accent ring, and
/// reveals a play button. Fills its parent's constraints (wrap in AspectRatio
/// or Expanded).
class HoverPosterArt extends ConsumerStatefulWidget {
  final BaseItemDto? item;
  final Widget? art; // custom artwork (e.g. a network poster) instead of [item]
  final Widget? overlay; // e.g. status badges, drawn above the art
  final Widget? hoverOverlay; // revealed on hover and clickable (e.g. a button)
  final VoidCallback? onTap;
  final double borderRadius;
  const HoverPosterArt(
      {super.key,
      this.item,
      this.art,
      this.overlay,
      this.hoverOverlay,
      this.onTap,
      this.borderRadius = 12})
      : assert(item != null || art != null);

  @override
  ConsumerState<HoverPosterArt> createState() => _HoverPosterArtState();
}

class _HoverPosterArtState extends ConsumerState<HoverPosterArt> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    // Resume sliver: universal, no setting. Only for real items with progress.
    final progress = item?.progressFraction;
    // Rating badge: opt-in (default off) and only from data already in the list
    // response (community/critic), so a grid never fires per-card lookups.
    final ratingMode = ref.watch(preferencesProvider
        .select((p) => p.asData?.value.cardRating ?? 'off'));
    final ratingBadge =
        item == null ? null : _cardRating(context, item, ratingMode);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hover ? 0.5 : 0.35),
                  blurRadius: _hover ? 20 : 12,
                  offset: const Offset(0, 6),
                ),
                // A soft accent glow blooms on hover so cards lift off the page.
                if (_hover)
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.45),
                    blurRadius: 26,
                    spreadRadius: -2,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.art ??
                      Hero(
                          tag: 'art-${widget.item!.id}',
                          child: MediaImage(item: widget.item!)),
                  if (widget.overlay != null) widget.overlay!,
                  if (widget.item != null) _WatchedBadge(item: widget.item!),
                  ?ratingBadge,
                  // Resume progress along the bottom, the way Jellyfin web and
                  // Plex show "how far in". Hidden by the hover-request overlay
                  // (Seerr cards pass `art`, not `item`, so they never have one).
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(widget.borderRadius),
                          bottomRight: Radius.circular(widget.borderRadius),
                        ),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                          valueColor: AlwaysStoppedAnimation(scheme.primary),
                        ),
                      ),
                    ),
                  // Accent ring + faint lift on hover — a "selectable" cue, not
                  // a play promise (tapping opens the detail page).
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius),
                          border: Border.all(color: scheme.primary, width: 2),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              scheme.primary.withValues(alpha: 0.0),
                              scheme.primary.withValues(alpha: 0.12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // A hover-revealed control (the Seerr Request button). Above
                  // the ring and NOT wrapped in IgnorePointer, so it's tappable;
                  // it also swallows the card's tap so requesting doesn't also
                  // open the detail page.
                  if (widget.hoverOverlay != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        opacity: _hover ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: !_hover,
                          child: widget.hoverOverlay!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card rating badge for [mode], or null when off / unavailable. Only uses
/// [BaseItemDto.criticRating] (RT critic %) and [communityRating] (star), both
/// present in the list response, so no per-card network lookups.
Widget? _cardRating(BuildContext context, BaseItemDto item, String mode) {
  if (mode == 'off') return null;
  final critic = item.criticRating; // 0..100
  final community = item.communityRating; // 0..10
  Widget critics() => _RatingBadge(
        label: '${critic!.round()}%',
        background: const Color(0xFFFA320A), // Rotten Tomatoes red
        foreground: Colors.white,
      );
  Widget star() => _RatingBadge(
        icon: Icons.star_rounded,
        iconColor: const Color(0xFFFFC107),
        label: community!.toStringAsFixed(1),
        background: Colors.black.withValues(alpha: 0.62),
        foreground: Colors.white,
      );
  switch (mode) {
    case 'critics':
      return critic != null ? critics() : null;
    case 'community':
      return community != null ? star() : null;
    default: // auto: critic score if present, else the community star
      if (critic != null) return critics();
      if (community != null) return star();
      return null;
  }
}

/// A small top-left rating pill on a poster card.
class _RatingBadge extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String label;
  final Color background;
  final Color foreground;
  const _RatingBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      left: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: iconColor ?? foreground),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// A corner badge showing watched state: a check for fully-played items, or the
/// number of unwatched episodes for a partly-watched series.
class _WatchedBadge extends StatelessWidget {
  final BaseItemDto item;
  const _WatchedBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = item.userData;
    final unplayed = data.unplayedItemCount;
    final showCheck = data.played;
    final showCount = !showCheck && item.isSeries && unplayed > 0;
    if (!showCheck && !showCount) return const SizedBox.shrink();
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: showCount
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: showCount ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: showCount ? BorderRadius.circular(11) : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
          ],
        ),
        alignment: Alignment.center,
        child: showCheck
            ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
            : Text('$unplayed',
                style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Portrait poster card (Recently Added, library grids).
class PosterCard extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;
  static const double width = 176;

  const PosterCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible so the poster shrinks to fit the row instead of ever
          // overflowing (no caution-tape). Rows are sized to give it full 2:3.
          Flexible(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: HoverPosterArt(item: item, onTap: onTap),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.productionYear != null)
            Text('${item.productionYear}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Width-flexible poster tile for grids (library browse, search results).
class PosterTile extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;

  const PosterTile({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = item.isEpisode
        ? (item.seriesName ?? '')
        : (item.productionYear?.toString() ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: HoverPosterArt(item: item, onTap: onTap)),
        const SizedBox(height: 6),
        Text(item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (subtitle.isNotEmpty)
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Landscape card with a progress bar (Continue Watching).
class ContinueCard extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;
  static const double width = 304;

  const ContinueCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.isEpisode ? (item.seriesName ?? item.name) : item.name;
    final subtitle = item.isEpisode
        ? _episodeLabel(item)
        : (item.productionYear?.toString() ?? '');

    return HoverLift(
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible so the artwork shrinks to fit instead of overflowing.
            Flexible(
              child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaImage(item: item, landscape: true),
                        if (item.progress > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 4,
                            backgroundColor: Colors.black45,
                          ),
                        ),
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  static String _episodeLabel(BaseItemDto item) {
    final s = item.parentIndexNumber;
    final e = item.indexNumber;
    if (s != null && e != null) return 'S$s:E$e · ${item.name}';
    return item.name;
  }
}

/// Landscape library tile with the library name overlaid.
class LibraryCard extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;
  static const double width = 268;

  const LibraryCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverLift(
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaImage(
                      item: item,
                      landscape: true,
                      placeholderIcon: Icons.video_library_rounded,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7)
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

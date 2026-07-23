import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'cached_image.dart';

/// Loads the best image for an item (portrait poster, or landscape art for
/// continue-watching / library tiles), with correct auth headers and a
/// graceful placeholder when there's no image or it fails to load.
class MediaImage extends ConsumerWidget {
  final BaseItemDto item;
  final bool landscape;
  final IconData placeholderIcon;

  /// Requested image dimensions. Defaults suit small cards; pass a larger
  /// [maxWidth] for full-width art (e.g. the Home hero) so it isn't upscaled.
  final int? maxWidth;
  final int? maxHeight;

  /// How the image is aligned when [BoxFit.cover] crops it. Biasing toward the
  /// top keeps faces/action visible when a wide band crops a 16:9 backdrop.
  final Alignment alignment;

  /// Sampling quality. Bump to medium for art that animates (e.g. the hero's
  /// Ken Burns zoom), where the default low sampling shimmers as it scales.
  final FilterQuality filterQuality;

  const MediaImage({
    super.key,
    required this.item,
    this.landscape = false,
    this.placeholderIcon = Icons.movie_rounded,
    this.maxWidth,
    this.maxHeight,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
  });

  ({String itemId, String type, String? tag})? _pick() {
    if (landscape) {
      // Episode "Primary" is a landscape still — ideal for Continue Watching.
      if (item.isEpisode && item.primaryImageTag != null) {
        return (itemId: item.id, type: 'Primary', tag: item.primaryImageTag!);
      }
      if (item.backdropImageTags.isNotEmpty) {
        return (
          itemId: item.id,
          type: 'Backdrop',
          tag: item.backdropImageTags.first
        );
      }
      if (item.primaryImageTag != null) {
        return (itemId: item.id, type: 'Primary', tag: item.primaryImageTag!);
      }
      return null;
    }
    // Portrait / poster. An episode's own Primary is a landscape still, so for
    // a poster use the SERIES poster instead (tag optional — the series
    // Primary is served without one too).
    if (item.isEpisode && item.seriesId != null) {
      return (
        itemId: item.seriesId!,
        type: 'Primary',
        tag: item.seriesPrimaryImageTag
      );
    }
    if (item.primaryImageTag != null) {
      return (itemId: item.id, type: 'Primary', tag: item.primaryImageTag!);
    }
    // Audio tracks often carry only the album's cover.
    if (item.albumPrimaryImageTag != null && item.albumId != null) {
      return (
        itemId: item.albumId!,
        type: 'Primary',
        tag: item.albumPrimaryImageTag!
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);

    final pick = _pick();
    if (session == null || pick == null) return _placeholder(context);

    final url = client.imageUrl(
      baseUrl: session.baseUrl,
      itemId: pick.itemId,
      type: pick.type,
      tag: pick.tag,
      maxWidth: maxWidth,
      maxHeight: maxWidth == null ? (maxHeight ?? 480) : maxHeight,
    );

    return CachedImage(
      url: url,
      fit: BoxFit.cover,
      alignment: alignment,
      headers: headers,
      filterQuality: filterQuality,
      errorBuilder: (context) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: scheme.onSurfaceVariant, size: 32),
    );
  }
}

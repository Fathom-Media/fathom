import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/image_cache.dart';
import 'shimmer.dart';

/// A disk-cached [ImageProvider], for the few places that need a provider (e.g.
/// CircleAvatar.foregroundImage) rather than a widget.
ImageProvider cachedImageProvider(String url) =>
    CachedNetworkImageProvider(url, cacheManager: fathomImageCache);

/// A network image backed by a persistent disk cache, so artwork survives an
/// app restart instead of re-downloading every launch. A drop-in for
/// `Image.network` across the app (Seerr TMDB art, Jellyfin art).
class CachedImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  /// Logical width to decode the image at. The bitmap is downsampled to about
  /// this many device pixels instead of the source's full resolution, which
  /// cuts memory and GPU upload for the many small poster/card images. Leave
  /// null for full-bleed art that fills the window.
  final double? cacheWidth;
  final Map<String, String>? headers;

  /// Sampling quality. Low is fine for static cards; use medium for art that
  /// animates (e.g. a Ken Burns zoom), where low sampling shimmers as it scales.
  final FilterQuality filterQuality;

  /// Shown while loading. Defaults to a shimmer.
  final Widget? placeholder;

  /// Shown when the image fails. Defaults to an empty box.
  final Widget Function(BuildContext context)? errorBuilder;

  const CachedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.cacheWidth,
    this.headers,
    this.filterQuality = FilterQuality.low,
    this.placeholder,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = cacheWidth != null ? (cacheWidth! * dpr).round() : null;
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: fathomImageCache,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      filterQuality: filterQuality,
      memCacheWidth: memW,
      httpHeaders: headers,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (context, _) =>
          placeholder ?? const ShimmerBox(borderRadius: BorderRadius.zero),
      errorWidget: (context, _, _) =>
          errorBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }
}

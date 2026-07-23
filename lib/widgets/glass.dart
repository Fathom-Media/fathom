import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../state/palette.dart';
import 'media_image.dart';

/// A frosted-glass surface: blurs whatever is painted behind it and lays a
/// translucent fill on top. Used for bars, sheets, and floating controls.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius borderRadius;
  final Border? border;

  /// Overrides the fill. Defaults to the theme surface at [opacity]; pass a dark
  /// tint (e.g. black at ~0.4) for the over-video variant used by the player
  /// chrome and live HUD, where a light surface would wash out the picture.
  final Color? color;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 24,
    this.opacity = 0.62,
    this.borderRadius = BorderRadius.zero,
    this.border,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? scheme.surface.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A full-bleed blurred backdrop drawn from an item's artwork, tinted with the
/// art's own signature color so the whole page takes on the poster's mood.
/// [child] is laid over it. Fathom's signature ambient look.
class BackdropBackground extends ConsumerWidget {
  final BaseItemDto item;
  final Widget child;
  final double blur;

  const BackdropBackground({
    super.key,
    required this.item,
    required this.child,
    this.blur = 48,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final accent = ref.watch(itemAccentProvider(item)).asData?.value;
    final tint = accent ?? scheme.primary;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Slightly over-scale so blurred edges never reveal the background.
        Transform.scale(
          scale: 1.15,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: MediaImage(item: item, landscape: true),
          ),
        ),
        // Art-driven accent glow from the top edge.
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: 0.45),
                tint.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0, 0.35, 0.7],
            ),
          ),
        ),
        // Surface scrim for text contrast.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface.withValues(alpha: 0.35),
                scheme.surface.withValues(alpha: 0.8),
                scheme.surface.withValues(alpha: 0.96),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// The Fathom app icon rendered inline (sidebar, splash, connect, about) so the
/// in-app branding matches the launcher/window icon. Backed by the bundled
/// icon asset, which already carries its rounded tile and transparent corners.
class FathomLogo extends StatelessWidget {
  final double size;
  const FathomLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/fathom.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      // Don't throw/log if the asset ever fails to resolve — show a glyph.
      errorBuilder: (context, _, _) => Icon(Icons.waves_rounded,
          size: size, color: Theme.of(context).colorScheme.primary),
    );
  }
}

/// The Fathom mark as a single-color glyph (arcs, play triangle, tentacles),
/// tinted to [color] so it tracks the app's theme/accent, the way the Seerr nav
/// icon does. Used where the full colored tile would clash with flat chrome
/// (e.g. the sidebar header).
class FathomGlyph extends StatelessWidget {
  final double size;
  final Color color;
  const FathomGlyph({super.key, this.size = 28, required this.color});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/fathom-mark.png',
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, _, _) =>
          Icon(Icons.waves_rounded, size: size, color: color),
    );
  }
}

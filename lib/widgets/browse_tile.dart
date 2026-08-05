import 'package:flutter/material.dart';

import 'motion.dart';
import 'tv_focus.dart';

/// A colourful gradient tile for browse clouds (Genres, Studios), so those
/// pages have some visual life instead of a flat chip wall. The colour is
/// derived from the label so a given genre always looks the same, without any
/// per-item artwork fetches.
class GradientBrowseTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Grabs focus on mount (TV): set on the first tile so the remote lands on
  /// content instead of the app bar.
  final bool autofocus;
  const GradientBrowseTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
  });

  Color _hue(int shift) {
    final h = ((label.hashCode.abs() % 360) + shift) % 360;
    return HSLColor.fromAHSL(1, h.toDouble(), 0.52, 0.42).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      child: TvFocusable(
        onTap: onTap,
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(14),
        child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_hue(0), _hue(40)],
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Icon(icon,
                      size: 60, color: Colors.white.withValues(alpha: 0.14)),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
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

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// The Movie Night Wheel's icon: Material's clapperboard glyph
/// ([Icons.movie_filter_rounded]) whose striped arm swings open and claps
/// shut. It claps when a surrounding [ClapOnHover] is hovered, touched, or
/// focused, or (with no [ClapOnHover] around it) when the icon itself is
/// hovered.
///
/// It animates the real glyph rather than a redrawn one so it matches the
/// static [Icons.movie_filter_rounded] used where only an IconData fits: the
/// glyph is drawn twice, once clipped to the slate and once clipped to the
/// arm, and the arm copy is rotated about the arm's bottom-left corner.
class ClapperIcon extends StatefulWidget {
  const ClapperIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  State<ClapperIcon> createState() => _ClapperIconState();
}

// Where the arm meets the slate in the glyph, as fractions of the icon box
// (measured from the font: the arm band sits above ~30% of the height, and
// the glyph's left edge is ~8% in).
const _split = 0.30;
const _hinge = Alignment(-0.83, _split * 2 - 1);

class _ClapperIconState extends State<ClapperIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  ValueNotifier<int>? _trigger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = _ClapScope.maybeOf(context);
    if (t != _trigger) {
      _trigger?.removeListener(_clap);
      _trigger = t?..addListener(_clap);
    }
  }

  @override
  void dispose() {
    _trigger?.removeListener(_clap);
    _c.dispose();
    super.dispose();
  }

  void _clap() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    if (!_c.isAnimating) _c.forward(from: 0);
  }

  // Open fast, slam shut, then a small rebound off the slate.
  static double _armAngle(double t) {
    const open = -0.45;
    if (t < 0.32) return open * Curves.easeOut.transform(t / 0.32);
    if (t < 0.5) return open * (1 - Curves.easeIn.transform((t - 0.32) / 0.18));
    final p = (t - 0.5) / 0.5;
    return -0.1 * math.sin(p * math.pi) * (1 - p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = widget.size ?? theme.size ?? 24;
    final color = widget.color ?? theme.color;
    final glyph = Icon(Icons.movie_filter_rounded, size: size, color: color);
    Widget child = AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (t == 0 || t == 1) return glyph;
        // The slate gives a little "thunk" as the arm lands.
        final squash = 1 - 0.08 * math.exp(-math.pow((t - 0.52) / 0.07, 2));
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scaleY: squash,
                alignment: Alignment.bottomCenter,
                child: ClipRect(clipper: const _Band(top: false), child: glyph),
              ),
              Transform.rotate(
                angle: _armAngle(t),
                alignment: _hinge,
                child: ClipRect(clipper: const _Band(top: true), child: glyph),
              ),
            ],
          ),
        );
      },
    );
    if (_trigger == null) {
      child = MouseRegion(onEnter: (_) => _clap(), child: child);
    }
    return child;
  }
}

class _Band extends CustomClipper<Rect> {
  const _Band({required this.top});
  final bool top;

  @override
  Rect getClip(Size size) => top
      ? Rect.fromLTRB(0, 0, size.width, size.height * _split)
      : Rect.fromLTRB(0, size.height * _split, size.width, size.height);

  @override
  bool shouldReclip(covariant _Band oldClipper) => oldClipper.top != top;
}

/// Makes every [ClapperIcon] inside [child] clap when [child] is hovered,
/// touched, or gains focus (the remote on TV), so hovering anywhere on a
/// button, not just its icon, sets it off.
class ClapOnHover extends StatefulWidget {
  const ClapOnHover({super.key, required this.child});
  final Widget child;

  @override
  State<ClapOnHover> createState() => _ClapOnHoverState();
}

class _ClapOnHoverState extends State<ClapOnHover> {
  final _trigger = ValueNotifier<int>(0);

  @override
  void dispose() {
    _trigger.dispose();
    super.dispose();
  }

  void _fire() => _trigger.value++;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) _fire();
      },
      child: MouseRegion(
        onEnter: (_) => _fire(),
        child: Listener(
          // Touch has no hover, so a press sets it off instead.
          onPointerDown: (e) {
            if (e.kind == PointerDeviceKind.touch) _fire();
          },
          child: _ClapScope(notifier: _trigger, child: widget.child),
        ),
      ),
    );
  }
}

class _ClapScope extends InheritedWidget {
  const _ClapScope({required this.notifier, required super.child});
  final ValueNotifier<int> notifier;

  static ValueNotifier<int>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ClapScope>()?.notifier;

  @override
  bool updateShouldNotify(_ClapScope old) => old.notifier != notifier;
}

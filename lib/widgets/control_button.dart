import 'package:flutter/material.dart';

/// A transport control (play/pause/stop/skip) that matches the video player's
/// buttons: it presses inward (scale 0.88, snappy easeOut) and springs back
/// (easeOutBack) on release, and warms toward a hover colour. This is the
/// shared version of the player's internal control so the radio, mini player
/// and music Now Playing all feel identical.
///
/// [grow] true (play/pause/skip) makes the button swell on hover; false (stop)
/// makes it CONTRACT on hover, so a terminating action reads as "closing in"
/// rather than "reaching out" — a small but deliberate difference in intent.
class ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final String? tooltip;

  /// Base glyph colour. Defaults to the theme's primary (accent).
  final Color? color;

  /// Colour on hover. Defaults to the base colour lightened toward white.
  final Color? hoverColor;

  /// Grow on hover (play/pause) vs contract (stop).
  final bool grow;

  const ControlButton({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    this.tooltip,
    this.color,
    this.hoverColor,
    this.grow = true,
  });

  @override
  State<ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<ControlButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.color ?? scheme.primary;
    final hover = widget.hoverColor ?? Color.lerp(base, Colors.white, 0.35)!;
    // Press wins over hover so a click reads as a deliberate inward press.
    final double scale = _pressed
        ? 0.88
        : _hover
            ? (widget.grow ? 1.16 : 0.9)
            : 1.0;

    Widget child = AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: _pressed ? 90 : 240),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      child: TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        tween: ColorTween(begin: base, end: _hover ? hover : base),
        builder: (context, color, _) =>
            Icon(widget.icon, size: widget.size, color: color),
      ),
    );

    child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      ),
    );

    final tip = widget.tooltip;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}

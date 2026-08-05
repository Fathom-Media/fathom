import 'package:flutter/material.dart';

import '../services/tv_mode.dart';

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

  /// Grabs focus on mount — used on TV so the remote lands on the primary
  /// transport (e.g. play/pause on the Now Playing screen).
  final bool autofocus;

  final FocusNode? focusNode;

  const ControlButton({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    this.tooltip,
    this.color,
    this.hoverColor,
    this.grow = true,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<ControlButton> {
  bool _hover = false;
  bool _pressed = false;
  // A D-pad/remote focus reads the same as a hover and adds a ring, so the
  // remote always shows which transport control it's on.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.color ?? scheme.primary;
    final hover = widget.hoverColor ?? Color.lerp(base, Colors.white, 0.35)!;
    final active = _hover || _focused;
    // Press wins over hover so a click reads as a deliberate inward press.
    final double scale = _pressed
        ? 0.88
        : active
            ? (widget.grow ? 1.16 : 0.9)
            : 1.0;

    Widget child = AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: _pressed ? 90 : 240),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      child: TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        tween: ColorTween(begin: base, end: active ? hover : base),
        builder: (context, color, _) =>
            Icon(widget.icon, size: widget.size, color: color),
      ),
    );

    child = FocusableActionDetector(
      // Focusable/activatable by the D-pad on TV only; off TV it stays a
      // mouse/touch control (not a keyboard tab stop), as it was before.
      enabled: isTvDevice,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: MouseRegion(
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
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _focused ? scheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    final tip = widget.tooltip;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}

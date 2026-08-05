import 'package:flutter/material.dart';

/// A player control that springs on hover/focus, presses inward on tap, warms to
/// the accent colour, and draws a focus ring for the D-pad. Shared by the
/// media_kit player chrome and the native ExoPlayer bar so both animate
/// identically. The child is any widget (usually an [Icon]); a genuine state
/// colour set on the child is left untouched, while a plain white glyph inherits
/// the white→accent tween.
class AnimatedControl extends StatefulWidget {
  final Widget child;
  final String? tooltip;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  const AnimatedControl({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
    this.focusNode,
  });

  @override
  State<AnimatedControl> createState() => _AnimatedControlState();
}

class _AnimatedControlState extends State<AnimatedControl> {
  bool _hover = false;
  bool _pressed = false;
  // D-pad/remote focus reads the same as a hover (accent + scale) and adds a
  // ring, so a TV remote always shows which control it's on.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final active = _hover || _focused;
    // Press wins over hover, so a click reads as a deliberate inward press even
    // while the pointer is over the button.
    final scale = _pressed ? 0.88 : (active ? 1.16 : 1.0);

    Widget child = AnimatedScale(
      scale: scale,
      // easeOutBack overshoots slightly, so the button springs rather than
      // glides; a shorter press duration makes the click feel snappy.
      duration: Duration(milliseconds: _pressed ? 90 : 240),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      // Padding keeps the tap target comfortably larger than the glyph.
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _focused ? Colors.black.withValues(alpha: 0.35) : null,
          border: Border.all(
            color: _focused ? accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        // Icons that don't set their own colour inherit this, so a plain white
        // control warms to the accent on hover/focus; genuine state colours
        // (theater active, live) set an explicit colour and are left untouched.
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          tween: ColorTween(
              begin: Colors.white, end: active ? accent : Colors.white),
          builder: (context, color, ch) => IconTheme.merge(
            data: IconThemeData(color: color),
            child: ch!,
          ),
          child: widget.child,
        ),
      ),
    );

    child = FocusableActionDetector(
      focusNode: widget.focusNode,
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
          child: child,
        ),
      ),
    );

    final tip = widget.tooltip;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}

/// An [AnimatedControl] with an [Icon] child. [size] defaults to the 22px bar
/// glyph; the phone ExoPlayer bar passes a larger size for its transport icons.
class AnimatedIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final double size;

  const AnimatedIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.focusNode,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedControl(
      onTap: onTap,
      tooltip: tooltip,
      focusNode: focusNode,
      // No explicit colour: inherits AnimatedControl's IconTheme (white, or
      // accent on hover).
      child: Icon(icon, size: size),
    );
  }
}

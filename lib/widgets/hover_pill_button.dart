import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// An action that rests as an icon-only pill and expands to reveal its label,
/// with a small pop on press. On desktop it expands on hover; on touch (no
/// hover) it expands while pressed, so a single tap still fires the action.
/// This is the on-a-page counterpart to the detail header/hero's
/// [HeaderActionButton] (which is styled for over an image).
///
/// [primary] fills the pill with the accent (a call to action, e.g. Subscribe);
/// [tinted] gives a soft accent wash (an active/"done" state, e.g. Subscribed);
/// otherwise it's a neutral surface pill.
class HoverPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool tinted;
  final bool primary;

  /// Fills the pill with this exact colour (white foreground), for semantic
  /// actions like Approve (green) / Decline (red). Overrides [primary]/[tinted].
  final Color? color;

  const HoverPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tinted = false,
    this.primary = false,
    this.color,
  });

  @override
  State<HoverPillButton> createState() => _HoverPillButtonState();
}

class _HoverPillButtonState extends State<HoverPillButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _pressed = false;

  // Touch platforms have no hover, so the label expands on press instead.
  static final bool _isTouch =
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _tapScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60),
  ]).animate(_tap);

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color fg;
    final Color bg;
    if (widget.color != null) {
      fg = Colors.white;
      bg = widget.color!;
    } else if (widget.primary) {
      fg = scheme.onPrimary;
      bg = scheme.primary;
    } else if (widget.tinted) {
      fg = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.14);
    } else {
      fg = scheme.onSurfaceVariant;
      bg = scheme.surfaceContainerHighest;
    }
    const h = 38.0;
    // Desktop reveals the label on hover; touch reveals it while pressed.
    final expanded = _isTouch ? _pressed : _hover;
    final icon = ScaleTransition(
      scale: _tapScale,
      child: Icon(widget.icon, size: 20, color: fg),
    );

    // Tooltip so the label is reachable without a hover (touch, quick glance).
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 500),
      child: Opacity(
        opacity: widget.onTap == null ? 0.5 : 1,
        // Raw pointer events drive the touch press-to-expand: InkWell's
        // highlight is deferred inside a scroll view, so holding wouldn't
        // expand. onPointerDown fires immediately.
        child: Listener(
          onPointerDown: widget.onTap == null
              ? null
              : (_) => setState(() => _pressed = true),
          onPointerUp: (_) {
            if (_pressed) setState(() => _pressed = false);
          },
          onPointerCancel: (_) {
            if (_pressed) setState(() => _pressed = false);
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Material(
              color: bg,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onTapDown:
                    widget.onTap == null ? null : (_) => _tap.forward(from: 0),
                child: AnimatedSize(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: h,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              icon,
                              const SizedBox(width: 8),
                              Text(widget.label,
                                  style: TextStyle(
                                      color: fg,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : SizedBox(width: h, child: Center(child: icon)),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

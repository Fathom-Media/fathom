import 'package:flutter/material.dart';

/// Whether the OS has asked for reduced motion. Big decorative animations (the
/// Ken Burns hero, entrance fades) honour this; hover feedback stays, since it's
/// pointer-driven, not autonomous motion.
bool reduceMotion(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  return mq != null && (mq.disableAnimations || mq.accessibleNavigation);
}

/// Lifts and scales its child slightly on pointer hover — the "alive" feel on
/// desktop. No-op on touch (there's no hover).
class HoverLift extends StatefulWidget {
  final Widget child;
  final double scale;

  const HoverLift({super.key, required this.child, this.scale = 1.04});

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Tints its child's background on pointer hover, the row equivalent of
/// [HoverLift] (scaling a full-width row looks wrong). No-op on touch.
class HoverHighlight extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  const HoverHighlight({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          color: _hover
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
              : Colors.transparent,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Fades + slides its child up on first appearance, staggered by [index] so a
/// row or grid flows in rather than snapping.
/// Items already animated in this session, so scrolling one out of a lazy list
/// and back doesn't replay its entrance (which reads as a "reload" flash).
/// Keyed by a caller-supplied stable id; bounded so it can't grow without end.
final Set<Object> _entranceSeen = <Object>{};

class EntranceFade extends StatefulWidget {
  final Widget child;
  final int index;

  /// A stable identity for this item (e.g. its tmdb id). When set, the entrance
  /// plays only the first time the item appears; later re-mounts (scrolling
  /// back, switching tabs) render immediately with no fade.
  final Object? onceKey;

  const EntranceFade(
      {super.key, required this.child, this.index = 0, this.onceKey});

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final key = widget.onceKey;
    // Already seen this item — show it instantly, no replayed fade.
    if (key != null && _entranceSeen.contains(key)) {
      _shown = true;
      return;
    }
    if (key != null) {
      if (_entranceSeen.length > 4000) _entranceSeen.clear();
      _entranceSeen.add(key);
    }
    final delayMs = (widget.index * 45).clamp(0, 450);
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: no slide/fade, just show the content.
    if (reduceMotion(context)) return widget.child;
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.08),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

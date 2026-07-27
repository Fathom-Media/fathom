import 'package:flutter/material.dart';

/// The app's unified search box: a rounded field that, on focus, draws an accent
/// outline that grows from the centre of the top and bottom edges outward until
/// the two halves meet at the sides, plus a soft accent glow. Use everywhere a
/// search input appears so they look and feel the same.
class SearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Optional external focus node (e.g. when the caller drives a suggestions
  /// dropdown off focus). When null, an internal node is used.
  final FocusNode? focusNode;

  /// Optional trailing widget (e.g. a loading spinner or a submit button). When
  /// null and the field has text, a clear (×) button is shown instead.
  final Widget? suffix;

  /// Called when the built-in clear (×) button is tapped.
  final VoidCallback? onClear;

  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
    this.suffix,
    this.onClear,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField>
    with SingleTickerProviderStateMixin {
  static const double _height = 48;
  static const double _radius = 24;

  FocusNode? _internalFocus;
  FocusNode get _focus => widget.focusNode ?? (_internalFocus ??= FocusNode());
  late final AnimationController _draw = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller.addListener(_onText);
    if (widget.autofocus) _draw.value = 1;
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _draw.forward();
    } else {
      _draw.reverse();
    }
  }

  void _onText() {
    if (mounted && widget.suffix == null) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    // Only dispose the node we created; a caller-supplied one is theirs.
    _internalFocus?.dispose();
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.isNotEmpty;

    return AnimatedBuilder(
      animation: _draw,
      builder: (context, child) {
        // Ease the raw controller value so the outline accelerates out of the
        // centre and the glow settles smoothly.
        final t = Curves.easeOut.transform(_draw.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: t > 0
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.26 * t),
                      blurRadius: 16 * t,
                      spreadRadius: 0.5 * t,
                    ),
                  ]
                : const [],
          ),
          child: CustomPaint(
            foregroundPainter: _CenterOutBorderPainter(
              progress: t,
              color: scheme.primary,
              strokeWidth: 2,
              radius: _radius,
            ),
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest
                    .withValues(alpha: 0.5 + 0.35 * t),
                borderRadius: BorderRadius.circular(_radius),
                // The resting hairline border fades as the accent outline draws
                // in, so there's never a double border.
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45 * (1 - t)),
                  width: 1,
                ),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Icon(Icons.search_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              cursorColor: scheme.primary,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              // Strip the global inputDecorationTheme (filled + a rounded
              // focused outline) so nothing draws inside our own frame.
              decoration: InputDecoration(
                hintText: widget.hint,
                filled: false,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          if (widget.suffix != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: widget.suffix,
            )
          else if (hasText)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              splashRadius: 18,
              color: scheme.onSurfaceVariant,
              onPressed: () {
                widget.controller.clear();
                widget.onChanged?.call('');
                widget.onClear?.call();
              },
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Paints a rounded-rect outline that grows from the centre of the top and
/// bottom edges outward (both directions at once), the four arcs meeting at the
/// left and right mid-points when [progress] reaches 1.
class _CenterOutBorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;

  _CenterOutBorderPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final i = strokeWidth / 2; // inset so the stroke isn't clipped
    final l = i, t = i, r = size.width - i, b = size.height - i;
    final rad =
        radius.clamp(0.0, ((r - l) / 2).clamp(0.0, (b - t) / 2)).toDouble();
    final cx = (l + r) / 2;
    final cy = (t + b) / 2;

    // Four quarter segments in a single clockwise winding, so every corner arc
    // is clockwise. TC = top-centre, RM = right-mid, BC = bottom-centre,
    // LM = left-mid.
    Path seg(Offset start, List<void Function(Path)> ops) {
      final p = Path()..moveTo(start.dx, start.dy);
      for (final op in ops) {
        op(p);
      }
      return p;
    }

    final rr = Radius.circular(rad);
    // A: TC -> RM
    final a = seg(Offset(cx, t), [
      (p) => p.lineTo(r - rad, t),
      (p) => p.arcToPoint(Offset(r, t + rad), radius: rr),
      (p) => p.lineTo(r, cy),
    ]);
    // B: RM -> BC
    final bSeg = seg(Offset(r, cy), [
      (p) => p.lineTo(r, b - rad),
      (p) => p.arcToPoint(Offset(r - rad, b), radius: rr),
      (p) => p.lineTo(cx, b),
    ]);
    // C: BC -> LM
    final c = seg(Offset(cx, b), [
      (p) => p.lineTo(l + rad, b),
      (p) => p.arcToPoint(Offset(l, b - rad), radius: rr),
      (p) => p.lineTo(l, cy),
    ]);
    // D: LM -> TC
    final d = seg(Offset(l, cy), [
      (p) => p.lineTo(l, t + rad),
      (p) => p.arcToPoint(Offset(l + rad, t), radius: rr),
      (p) => p.lineTo(cx, t),
    ]);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // A and C grow from their START (TC, BC); B and D grow from their END
    // (BC, TC) — so both TC and BC sprout two arcs that reach the sides.
    _drawFromStart(canvas, a, paint);
    _drawFromStart(canvas, c, paint);
    _drawFromEnd(canvas, bSeg, paint);
    _drawFromEnd(canvas, d, paint);
  }

  void _drawFromStart(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  void _drawFromEnd(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      canvas.drawPath(
          m.extractPath(m.length * (1 - progress), m.length), paint);
    }
  }

  @override
  bool shouldRepaint(_CenterOutBorderPainter old) =>
      old.progress != progress || old.color != color;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's dropdown: a rounded pill showing the current value with a chevron
/// that flips as it opens, and a menu that fades + scales in from the top with
/// hover highlights and the current value marked. One widget so every dropdown
/// in the app looks and animates the same.
class AppDropdown<T> extends StatefulWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  /// Optional leading glyph shown inside the pill (e.g. a filter icon).
  final IconData? leading;

  const AppDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.leading,
  });

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _pillKey = GlobalKey();
  final _portal = OverlayPortalController();
  bool _open = false;
  bool _hover = false;
  double _pillWidth = 120;

  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    final w = _pillKey.currentContext?.size?.width;
    if (w != null && w > 40) _pillWidth = w;
    _portal.show();
    setState(() => _open = true);
    _anim.forward(from: 0);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _anim.reverse().then((_) {
      if (mounted && !_open) _portal.hide();
    });
  }

  void _select(T v) {
    _close();
    if (v != widget.value) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = widget.options[widget.value] ??
        (widget.options.isNotEmpty ? widget.options.values.first : '');
    final fg = _open ? scheme.primary : scheme.onSurface;
    final bg = _open
        ? scheme.primary.withValues(alpha: 0.12)
        : (_hover
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerHigh);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _overlay(scheme),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: AnimatedContainer(
              key: _pillKey,
              duration: const Duration(milliseconds: 140),
              constraints: const BoxConstraints(minWidth: 96),
              padding: EdgeInsets.fromLTRB(widget.leading != null ? 11 : 14, 9, 8, 9),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _open
                        ? scheme.primary.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.leading != null) ...[
                    Icon(widget.leading, size: 18, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(ColorScheme scheme) {
    final width = math.max(_pillWidth, 160.0);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          // Anchored to the pill's right edge so a wider menu grows leftward and
          // stays on screen (these sit right-aligned in a settings row).
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_anim.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, -6 * (1 - t)),
                  child: Transform.scale(
                    scale: 0.96 + 0.04 * t,
                    alignment: Alignment.topRight,
                    child: child,
                  ),
                ),
              );
            },
            child: Material(
              elevation: 8,
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in widget.options.entries)
                          _DropdownRow(
                            label: e.value,
                            selected: e.key == widget.value,
                            onTap: () => _select(e.key),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownRow extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DropdownRow(
      {required this.label, required this.selected, required this.onTap});

  @override
  State<_DropdownRow> createState() => _DropdownRowState();
}

class _DropdownRowState extends State<_DropdownRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : (_hover
                  ? scheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected ? scheme.primary : scheme.onSurface,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

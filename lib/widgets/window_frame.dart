import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double _titleBarHeight = 34;

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Draws a seamless, transparent title bar (drag region + window buttons) over
/// the content, Fladder-style: full-bleed art runs to the very top edge while
/// app bars drop below the bar (we inject an equivalent top padding so their
/// back/action buttons never sit under the window controls). No-op off desktop.
class WindowFrame extends StatelessWidget {
  final Widget child;
  const WindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        // App content sees the top strip as a safe-area inset, so Scaffolds and
        // AppBars keep their chrome below the window buttons. Full-bleed slivers
        // (hero, backdrops) ignore padding and run edge-to-edge behind the bar.
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(top: mq.padding.top + _titleBarHeight),
          ),
          child: child,
        ),
        const Positioned(top: 0, left: 0, right: 0, child: _TitleBar()),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _titleBarHeight,
      child: Row(
        children: [
          Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          _WinButton(
            icon: Icons.remove_rounded,
            action: _WinAction.minimize,
          ),
          _WinButton(
            icon: Icons.crop_square_rounded,
            iconSize: 14,
            action: _WinAction.maximize,
          ),
          _WinButton(
            icon: Icons.close_rounded,
            hoverColor: Color(0xFFE81123),
            action: _WinAction.close,
          ),
        ],
      ),
    );
  }
}

enum _WinAction { minimize, maximize, close }

class _WinButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final Color? hoverColor;
  final _WinAction action;
  const _WinButton({
    required this.icon,
    required this.action,
    this.iconSize = 18,
    this.hoverColor,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  Future<void> _run() async {
    switch (widget.action) {
      case _WinAction.minimize:
        await windowManager.minimize();
      case _WinAction.maximize:
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      case _WinAction.close:
        await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final closeHover = widget.hoverColor != null && _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _run,
        child: Container(
          width: 46,
          height: _titleBarHeight,
          color: closeHover
              ? widget.hoverColor
              : (_hover
                  ? scheme.onSurface.withValues(alpha: 0.12)
                  : Colors.transparent),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: closeHover ? Colors.white : scheme.onSurface,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
      ),
    );
  }
}

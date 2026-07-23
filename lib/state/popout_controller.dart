import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Drives the "pop out to desktop" mode: the whole Fathom window shrinks into a
/// small, always-on-top, 16:9 floating video the user can drag anywhere (any
/// monitor) and freely resize. Restoring puts the window back where it was.
///
/// This is a SINGLE-window pop-out (the rest of the app is covered while out),
/// deliberately: a true second window would need Flutter multi-window + a second
/// mpv player, which is heavy and fragile on Linux. The in-app mini player
/// (for multitasking inside Fathom) stays as it was; this is the escape hatch to
/// the desktop.
class PopoutController extends Notifier<bool> {
  Size? _prevSize;
  bool _wasMaximized = false;

  @override
  bool build() => false;

  Future<void> enter() async {
    if (state) return;
    try {
      _prevSize = await windowManager.getSize();
      // A maximized or fullscreen window ignores setSize on Wayland/KWin, so the
      // pop-out would stay full-screen. Drop those states first, then it can
      // shrink to the small floating size. Remember maximized so exit restores it.
      _wasMaximized = await windowManager.isMaximized();
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (_wasMaximized) await windowManager.unmaximize();
      // Allow the window to shrink well below the app's normal minimum.
      await windowManager.setMinimumSize(const Size(240, 135));
      await windowManager.setAspectRatio(16 / 9);
      await windowManager.setSize(const Size(480, 270));
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {}
    state = true;
  }

  Future<void> exit() async {
    if (!state) return;
    try {
      await windowManager.setAlwaysOnTop(false);
      // Clear the 16:9 lock so the restored window can be any shape again.
      await windowManager.setAspectRatio(0);
      await windowManager.setMinimumSize(const Size(900, 620));
      // Put the window back the way it was: re-maximize if it had been, else
      // restore the exact pre-pop-out size.
      if (_wasMaximized) {
        await windowManager.maximize();
      } else {
        final prev = _prevSize;
        if (prev != null) await windowManager.setSize(prev);
      }
    } catch (_) {}
    state = false;
  }
}

final popoutProvider =
    NotifierProvider<PopoutController, bool>(PopoutController.new);

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// Makes a whole reorderable row draggable from ANYWHERE on it, the right way
/// for each input:
///  - Desktop (mouse): an immediate press-drag. A quick click still passes
///    through as a tap, and the wheel still scrolls, so nothing is lost.
///  - Touch: a long-press, so a normal swipe still scrolls the list and a tap
///    still activates the row.
///
/// [ReorderableDelayedDragStartListener] (long-press) does not fire for a mouse,
/// which is why a desktop user could previously only drag from the handle.
Widget dragAnywhere({
  Key? key,
  required int index,
  required Widget child,
}) {
  final isTouch = Platform.isAndroid || Platform.isIOS;
  return isTouch
      ? ReorderableDelayedDragStartListener(
          key: key, index: index, child: child)
      : ReorderableDragStartListener(key: key, index: index, child: child);
}

/// The subdued drag-grip colour: visible but greyed back so it reads as a hint,
/// not a control.
Color dragGripColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

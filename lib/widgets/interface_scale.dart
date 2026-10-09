import 'package:flutter/widgets.dart';

/// Draws everything below it [scale] times bigger: layout, text, icons, hit
/// areas and all. The Interface Size setting, for screens where the desktop's
/// own scaling leaves Fathom too small (a 4K monitor at 100%, say).
///
/// Descendants see a screen [scale] times smaller in logical pixels with a
/// [scale] times higher pixel ratio, so layouts, breakpoints and image sizes
/// all work as they would on a genuinely denser display, and the result is
/// painted scaled up, which keeps text and icons sharp rather than stretched.
/// Hit testing and focus go through the same transform, so a click lands on
/// what's drawn under it. Code turning an event's screen position into an
/// overlay position must use `globalToLocal` (see context_menu.dart).
class InterfaceScale extends StatelessWidget {
  const InterfaceScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.001) return child;
    final mq = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth / scale,
          constraints.maxHeight / scale);
      return MediaQuery(
        data: mq.copyWith(
          size: mq.size / scale,
          devicePixelRatio: mq.devicePixelRatio * scale,
          padding: mq.padding / scale,
          viewPadding: mq.viewPadding / scale,
          viewInsets: mq.viewInsets / scale,
          systemGestureInsets: mq.systemGestureInsets / scale,
        ),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      );
    });
  }
}

/// The interface size the automatic setting picks for a monitor [widthPx]
/// device pixels and [widthMm] millimetres wide, with the desktop's own
/// scale factor [systemScale].
///
/// Deliberately narrow, so nobody's current setup changes by surprise: only
/// when the desktop leaves scaling at 100%, and only on a high-resolution
/// screen that is also dense. A 27" 4K goes to 150%, a 13" 1440p laptop to
/// 200%; 1080p screens, 1440p monitors and 4K TVs stay as they are. A monitor
/// reporting no believable physical size is left alone too.
double autoInterfaceScale({
  required int widthPx,
  required int widthMm,
  required int systemScale,
}) {
  if (systemScale != 1 || widthPx < 2500 || widthMm < 150) return 1.0;
  final dpi = widthPx / (widthMm / 25.4);
  if (dpi < 130) return 1.0;
  return dpi >= 200 ? 2.0 : 1.5;
}

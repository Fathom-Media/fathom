import 'package:fathom/widgets/context_menu.dart';
import 'package:fathom/widgets/interface_scale.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('autoInterfaceScale', () {
    double auto(int px, double inches, {int scale = 1}) => autoInterfaceScale(
        widthPx: px, widthMm: (inches * 25.4).round(), systemScale: scale);

    // Widths of common screens, in inches (16:9 unless noted).
    test('dense high-resolution screens size up', () {
      expect(auto(3840, 23.5), 1.5); // 27" 4K, 163 dpi
      expect(auto(3840, 20.9), 1.5); // 24" 4K, 184 dpi
      expect(auto(3840, 27.9), 1.5); // 32" 4K, 138 dpi
      expect(auto(2560, 11.3), 2.0); // 13" 1440p laptop, 226 dpi
    });

    test('everything else is left exactly as it is', () {
      expect(auto(1920, 13.6), 1.0); // 15.6" 1080p laptop
      expect(auto(1920, 12.2), 1.0); // 14" 1080p laptop, dense but not high-res
      expect(auto(2560, 23.5), 1.0); // 27" 1440p monitor
      expect(auto(3840, 37.5), 1.0); // 43" 4K monitor
      expect(auto(3840, 47.9), 1.0); // 55" 4K TV
    });

    test('never stacks on top of the desktop scaling, or trusts a bogus size', () {
      expect(auto(3840, 23.5, scale: 2), 1.0); // desktop already at 200%
      expect(autoInterfaceScale(widthPx: 3840, widthMm: 0, systemScale: 1), 1.0);
      expect(autoInterfaceScale(widthPx: 3840, widthMm: 40, systemScale: 1), 1.0);
    });
  });

  group('InterfaceScale', () {
    Widget app(double scale, Widget home) => MaterialApp(
          builder: (context, child) =>
              InterfaceScale(scale: scale, child: child!),
          home: home,
        );

    testWidgets('children see a smaller, denser screen', (tester) async {
      late MediaQueryData seen;
      await tester.pumpWidget(app(2, Builder(builder: (context) {
        seen = MediaQuery.of(context);
        return const SizedBox();
      })));
      final real = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(seen.size, real / 2);
      expect(seen.devicePixelRatio, tester.view.devicePixelRatio * 2);
    });

    testWidgets('a click lands on what is drawn under it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(app(
        2,
        Align(
          alignment: Alignment.topLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 100, height: 50),
          ),
        ),
      ));
      // 100x50 drawn at 200% covers 200x100 of the window.
      await tester.tapAt(const Offset(190, 90));
      expect(taps, 1);
      await tester.tapAt(const Offset(210, 90));
      expect(taps, 1);
    });

    testWidgets('a right-click menu opens where the click was', (tester) async {
      await tester.pumpWidget(app(
        1.5,
        Scaffold(
          body: Builder(
            builder: (context) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapUp: (d) => showContextMenu(context,
                  at: d.globalPosition,
                  actions: [
                    ContextMenuAction(
                        icon: Icons.play_arrow, label: 'Play', onTap: () {}),
                  ]),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ));
      const click = Offset(300, 240);
      await tester.tapAt(click, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final item = tester.getTopLeft(find.byType(PopupMenuItem<VoidCallback>));
      // The menu opens at the click, in the same window coordinates, not
      // scaled away from it (the old code put it half as far out again).
      expect(item.dx, closeTo(click.dx, 2));
      expect(item.dy, inInclusiveRange(click.dy, click.dy + 20));
    });

    testWidgets('at 100% it adds nothing to the tree', (tester) async {
      await tester.pumpWidget(app(1, const SizedBox()));
      expect(find.byType(FittedBox), findsNothing);
    });
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/widgets/clapper_icon.dart';

// The Movie Night Wheel icon claps (arm swings open and shut) when anywhere on
// its button is hovered, not just the icon, and rests as the plain glyph.
void main() {
  Finder armClips() => find.descendant(
      of: find.byType(ClapperIcon), matching: find.byType(ClipRect));

  testWidgets('hovering the button claps, then it settles', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ClapOnHover(
            child: SizedBox(
              width: 200,
              height: 60,
              child: FilledButton.icon(
                onPressed: () {},
                icon: const ClapperIcon(),
                label: const Text('Start'),
              ),
            ),
          ),
        ),
      ),
    ));
    expect(armClips(), findsNothing);

    // Hover the far end of the button, away from the icon itself.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Start')) + const Offset(40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(armClips(), findsNWidgets(2));

    await tester.pump(const Duration(milliseconds: 600));
    expect(armClips(), findsNothing);
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
  });
}

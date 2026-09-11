import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/widgets/spin_wheel.dart';

// SpinWheel's poster art fills each wedge (not just a small thumbnail chip),
// clipped to the wedge's own pie-slice shape via a CustomClipper. That clip
// sits between the Stack and each poster's own Positioned, which is exactly
// the shape of a real "Incorrect use of ParentDataWidget" trap if the
// Positioned ends up nested inside the ClipPath instead of the other way
// around. This pins that it renders cleanly across a range of item counts
// (2 is the minimum spinnable count, higher counts get progressively
// thinner wedges) and sizes, with no layout exceptions.
BaseItemDto _fakeItem(int i) =>
    BaseItemDto(id: 'item-$i', name: 'Movie Title Number $i: A Long Subtitle');

Widget _harness({required int count, required double size}) {
  return ProviderScope(
    overrides: [deviceIdProvider.overrideWithValue('test-device')],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SpinWheel(
            items: List.generate(count, _fakeItem),
            size: size,
            onLanded: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(MediaKit.ensureInitialized);

  for (final count in [2, 3, 5, 8]) {
    testWidgets('renders cleanly with $count items', (tester) async {
      await tester.pumpWidget(_harness(count: count, size: 320));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders cleanly at the smallest clamped size', (tester) async {
    await tester.pumpWidget(_harness(count: 4, size: 220));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

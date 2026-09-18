import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  Future<List<int>> pumpWheel(WidgetTester tester) async {
    final landed = <int>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [deviceIdProvider.overrideWithValue('test-device')],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SpinWheel(
              items: List.generate(4, _fakeItem),
              size: 320,
              onLanded: landed.add,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return landed;
  }

  testWidgets('a flick across the wheel spins it and lands', (tester) async {
    final landed = await pumpWheel(tester);
    final state = tester.state<SpinWheelState>(find.byType(SpinWheel));
    // A fast swipe across the upper half is a clockwise flick.
    final c = tester.getCenter(find.byType(SpinWheel));
    await tester.flingFrom(c + const Offset(-90, -90), const Offset(180, 0), 2500);
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.isBusy, isTrue);
    for (var i = 0; i < 130; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(landed, hasLength(1));
    expect(state.isBusy, isFalse);
  });

  testWidgets('a slow drag turns the wheel without spinning it',
      (tester) async {
    final landed = await pumpWheel(tester);
    final state = tester.state<SpinWheelState>(find.byType(SpinWheel));
    final c = tester.getCenter(find.byType(SpinWheel));
    final gesture = await tester.startGesture(c + const Offset(-90, -90));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.isBusy, isFalse);
    expect(landed, isEmpty);
  });

  testWidgets('titles get their wedge\'s real room on a big wheel',
      (tester) async {
    // A fixed 130px label cap used to ellipsize long titles even on a big
    // wheel with plenty of space. The label now spans its wedge's width.
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(count: 3, size: 800));
    await tester.pump();
    final width = tester.getSize(find.text(_fakeItem(0).name)).width;
    expect(width, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders cleanly at the smallest clamped size', (tester) async {
    await tester.pumpWidget(_harness(count: 4, size: 220));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wheel rasterizes itself while it spins', (tester) async {
    // Measured on a 120Hz phone: repainting every clipped poster, fill and
    // label each frame cost ~4.4ms a frame against an 8.3ms budget, and the
    // spin visibly stuttered. Snapshotting for the duration of the spin turns
    // those frames into one rotated texture. It has to go off again at the
    // end, or the landing highlight would animate under a frozen picture.
    await tester.pumpWidget(_harness(count: 5, size: 320));
    await tester.pump();
    final snapshot =
        tester.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller;
    expect(snapshot.allowSnapshotting, isFalse);

    final state = tester.state<SpinWheelState>(find.byType(SpinWheel));
    state.spin();
    await tester.pump(const Duration(milliseconds: 50));
    expect(snapshot.allowSnapshotting, isTrue, reason: 'snapshot while spinning');

    for (var i = 0; i < 130; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.isBusy, isFalse);
    expect(snapshot.allowSnapshotting, isFalse,
        reason: 'back to live painting once it lands');
  });
}

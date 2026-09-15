import 'dart:ui'
    show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/fold.dart';

// The bounds and postures here are copied from a real foldable's log
// (2026-09-12), not invented: a zero-thickness crease reported at y=426 when
// the device is held in tabletop, and at x=426 when it's held like a book.
Widget _screen({required Size size, List<DisplayFeature> features = const []}) {
  return MediaQuery(
    data: MediaQueryData(size: size, displayFeatures: features),
    child: Builder(builder: (context) {
      final fold = FoldInfo.of(context);
      return Text(
        fold == null
            ? 'none'
            : '${fold.axis.name} @${fold.position} '
                'tabletop=${fold.isTabletop} book=${fold.isBook}',
        textDirection: TextDirection.ltr,
      );
    }),
  );
}

DisplayFeature _fold(Rect bounds, DisplayFeatureState state) => DisplayFeature(
      bounds: bounds,
      type: DisplayFeatureType.fold,
      state: state,
    );

void main() {
  testWidgets('a plain screen has no fold', (tester) async {
    await tester.pumpWidget(_screen(size: const Size(443, 961)));
    expect(find.text('none'), findsOneWidget);
  });

  testWidgets('a camera cutout is not a fold', (tester) async {
    await tester.pumpWidget(_screen(
      size: const Size(852, 883),
      features: const [
        DisplayFeature(
          bounds: Rect.fromLTRB(796, 0, 852, 66),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ],
    ));
    expect(find.text('none'), findsOneWidget);
  });

  testWidgets('half-folded with a crease across the middle is tabletop',
      (tester) async {
    await tester.pumpWidget(_screen(
      size: const Size(883, 852),
      features: [
        _fold(const Rect.fromLTRB(0, 426, 883, 426),
            DisplayFeatureState.postureHalfOpened),
      ],
    ));
    expect(find.text('horizontal @426.0 tabletop=true book=false'),
        findsOneWidget);
  });

  testWidgets('half-folded the other way is book, not tabletop',
      (tester) async {
    await tester.pumpWidget(_screen(
      size: const Size(852, 883),
      features: [
        _fold(const Rect.fromLTRB(426, 0, 426, 883),
            DisplayFeatureState.postureHalfOpened),
      ],
    ));
    expect(find.text('vertical @426.0 tabletop=false book=true'),
        findsOneWidget);
  });

  testWidgets('flat is a fold but not a posture to design around',
      (tester) async {
    await tester.pumpWidget(_screen(
      size: const Size(883, 852),
      features: [
        _fold(const Rect.fromLTRB(0, 426, 883, 426),
            DisplayFeatureState.postureFlat),
      ],
    ));
    expect(find.text('horizontal @426.0 tabletop=false book=false'),
        findsOneWidget);
  });

  group('tabletopFold', () {
    Widget probe(List<DisplayFeature> features) => MediaQuery(
          data: MediaQueryData(
              size: const Size(883, 852), displayFeatures: features),
          child: Builder(
            builder: (context) => Text(
              tabletopFold(context)?.position.toString() ?? 'none',
              textDirection: TextDirection.ltr,
            ),
          ),
        );
    final tabletop = [
      _fold(const Rect.fromLTRB(0, 426, 883, 426),
          DisplayFeatureState.postureHalfOpened),
    ];

    testWidgets('a half-folded phone reports its crease', (tester) async {
      await tester.pumpWidget(probe(tabletop));
      expect(find.text('426.0'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a flat phone is not in tabletop', (tester) async {
      await tester.pumpWidget(probe([
        _fold(const Rect.fromLTRB(0, 426, 883, 426), DisplayFeatureState.postureFlat),
      ]));
      expect(find.text('none'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('desktop never is, whatever it reports', (tester) async {
      await tester.pumpWidget(probe(tabletop));
      expect(find.text('none'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/screens/movie_wheel_screen.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/watchlist.dart';
import 'package:fathom/widgets/spin_wheel.dart';

// Drives the Movie Night Wheel end to end (setup, a real spin, the wedge
// collapse, the result screen) at phone and desktop sizes, so a layout
// error anywhere in the flow fails here instead of on a device.

class _FakePrefs extends PreferencesController {
  _FakePrefs(this.initial);
  final Prefs initial;

  @override
  Future<Prefs> build() async => initial;

  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? initial));
  }
}

class _FakeWatchlist extends WatchlistController {
  _FakeWatchlist(this.items);
  final List<BaseItemDto> items;

  @override
  Future<List<BaseItemDto>> build() async => items;
}

BaseItemDto _item(int i) => BaseItemDto(
      id: 'item-$i',
      name: 'A Fairly Long Movie Title Number $i',
      productionYear: 2000 + i,
      runTimeTicks: 6000000000 * (90 + i),
      overview: 'A synopsis long enough to wrap across several lines on a '
          'phone so the result screen has to lay out real text.',
      genres: const ['Comedy', 'Drama'],
    );

Widget _app({required int count, required String mode}) {
  return ProviderScope(
    overrides: [
      deviceIdProvider.overrideWithValue('test-device'),
      preferencesProvider.overrideWith(
          () => _FakePrefs(Prefs(movieWheelMode: mode, movieWheelSound: false))),
      watchlistProvider
          .overrideWith(() => _FakeWatchlist(List.generate(count, _item))),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MovieWheelScreen(),
    ),
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

void main() {
  setUpAll(MediaKit.ensureInitialized);

  for (final size in const [Size(360, 740), Size(1280, 800)]) {
    for (final mode in const ['last', 'single']) {
      testWidgets('plays a full $mode game at ${size.width.toInt()} wide',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_app(count: 2, mode: mode));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Start with 2 Titles'), findsOneWidget);

        await tester.tap(find.text('Start with 2 Titles'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Tap the wheel to spin, then run the whole spin, the landing
        // highlight, any result overlay, the collapse, and the reveal.
        await tester.tap(find.byType(GestureDetector).first);
        await _pumpFor(tester, const Duration(seconds: 14));
        expect(tester.takeException(), isNull);
        expect(find.text("TONIGHT'S PICK"), findsOneWidget);

        await _pumpFor(tester, const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
      });
    }
  }

  Future<void> startGame(WidgetTester tester, int count, String mode) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(count: count, mode: mode));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Start with $count Titles'));
    await tester.pump();
  }

  testWidgets('best of 3 always reaches a winner, tiebreak included',
      (tester) async {
    await startGame(tester, 3, 'best3');
    // Worst case is three different titles then a tiebreak spin.
    for (var spin = 0; spin < 4; spin++) {
      if (find.text("TONIGHT'S PICK").evaluate().isNotEmpty) break;
      await tester.tap(find.byType(SpinWheel));
      await _pumpFor(tester, const Duration(seconds: 14));
      expect(tester.takeException(), isNull);
    }
    expect(find.text("TONIGHT'S PICK"), findsOneWidget);
    await _pumpFor(tester, const Duration(seconds: 4));
  });

  testWidgets('undo brings an eliminated title back', (tester) async {
    await startGame(tester, 3, 'last');
    expect(find.text('3 Left'), findsOneWidget);
    await tester.tap(find.byType(SpinWheel));
    await _pumpFor(tester, const Duration(seconds: 13));
    expect(find.text('2 Left'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('3 Left'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  for (final size in const [Size(740, 360), Size(640, 320)]) {
    testWidgets('the wheel fits a phone held sideways at $size',
        (tester) async {
      // A fixed 220px minimum made the wheel taller than the space left in
      // landscape; the Stack clipped it silently, cropping the wheel's bottom.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(count: 3, mode: 'last'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Start with 3 Titles'), warnIfMissed: false);
      await tester.pump();
      final box = tester.getSize(find.byType(SpinWheel));
      expect(box.height, moreOrLessEquals(box.width + 24));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('filters narrow the list without layout errors', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(count: 4, mode: 'best3'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Start with 4 Titles'), findsOneWidget);
    // The setup controls must leave real room for the list on a phone: the
    // first title should be on screen, above the pinned Start button.
    final firstTitle = tester.getRect(find.text(_item(0).name));
    final start = tester.getRect(find.text('Start with 4 Titles'));
    expect(firstTitle.bottom, lessThan(start.top));

    await tester.ensureVisible(find.text('Select None'));
    await tester.tap(find.text('Select None'));
    await tester.pump();
    expect(find.text('Pick at Least 2 Titles'), findsOneWidget);

    await tester.ensureVisible(find.text('Select All'));
    await tester.tap(find.text('Select All'));
    await tester.pump();
    expect(find.text('Start with 4 Titles'), findsOneWidget);
    await tester.ensureVisible(find.text('Under 2 Hours'));
    await tester.tap(find.text('Under 2 Hours'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

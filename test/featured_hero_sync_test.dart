import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/widgets/featured_hero.dart';

// A reload used to hand the carousel an empty list for a moment. It tore its
// pages down and rebuilt them at page 0, while the details overlay kept the old
// page: a real Home showed an Everybody Loves Raymond backdrop under The Legend
// of Tarzan's logo and overview. The backdrop and the details must always be
// the same title.
List<BaseItemDto> _titles(List<String> names) => [
      for (final n in names) BaseItemDto(id: n, name: n, type: 'Movie'),
    ];

Widget _app(List<BaseItemDto> items) => ProviderScope(
      overrides: [deviceIdProvider.overrideWithValue('test-device')],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: FeaturedHero(items: items)),
        ),
      ),
    );

int _backdropPage(WidgetTester tester) =>
    (tester.widget<PageView>(find.byType(PageView)).controller!.page ?? 0)
        .round();

void main() {
  setUpAll(MediaKit.ensureInitialized);

  Future<void> goTo(WidgetTester tester, int page) async {
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(page);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a reload through an empty list keeps backdrop and details together',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final names = ['Raymond', 'Lanterns', 'Ted Lasso', 'Tarzan', 'Heat', 'Up'];
    await tester.pumpWidget(_app(_titles(names)));
    await tester.pump();
    await goTo(tester, 3);
    expect(find.text('Tarzan'), findsWidgets);

    // What a refresh used to do.
    await tester.pumpWidget(_app(const []));
    await tester.pump();
    await tester.pumpWidget(_app(_titles(names)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final page = _backdropPage(tester);
    expect(find.text(names[page]), findsWidgets,
        reason: 'the details must describe the backdrop being shown '
            '(backdrop is on ${names[page]})');
  });

  testWidgets('a reordered list keeps showing the same title', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_titles(['A', 'B', 'C', 'D'])));
    await tester.pump();
    await goTo(tester, 2); // on "C"

    // The watching list re-sorted: C moved to the front.
    await tester.pumpWidget(_app(_titles(['C', 'A', 'B', 'D'])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_backdropPage(tester), 0, reason: 'followed C to its new position');
    expect(find.text('C'), findsWidgets);
  });
}

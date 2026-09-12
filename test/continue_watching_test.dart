import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/widgets/media_cards.dart';

// Continue Watching's card had no menu of any kind, only a tap, so there was
// nowhere to offer "Remove from Continue Watching" (or anything else a poster
// offers). It now carries the same item menu: long-press, right-click, or the
// hover hamburger.
BaseItemDto _resumable() => const BaseItemDto(
      id: 'm1',
      name: 'Arrival',
      type: 'Movie',
      productionYear: 2016,
      runTimeTicks: 60000000000,
      userData: UserItemData(playbackPositionTicks: 12000000000),
    );

Widget _app(Widget child) => ProviderScope(
      overrides: [deviceIdProvider.overrideWithValue('test-device')],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('a Continue Watching card opens the item menu on long-press',
      (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      height: 260,
      child: ContinueCard(item: _resumable(), onTap: () {}),
    )));
    await tester.pump();

    await tester.longPress(find.byType(ContinueCard));
    await tester.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.actionRemoveFromContinueWatching), findsOneWidget,
        reason: 'the row exists for exactly this action');
    expect(find.text(l.detailMarkWatched), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the hamburger appears on hover', (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      height: 260,
      child: ContinueCard(item: _resumable(), onTap: () {}),
    )));
    await tester.pump();

    Finder hamburger() => find.descendant(
        of: find.byType(ContinueCard),
        matching: find.byIcon(Icons.more_vert_rounded));
    expect(tester.widget<AnimatedOpacity>(
            find.ancestor(of: hamburger(), matching: find.byType(AnimatedOpacity))
                .first)
        .opacity, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ContinueCard)));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(
            find.ancestor(of: hamburger(), matching: find.byType(AnimatedOpacity))
                .first)
        .opacity, 1);
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

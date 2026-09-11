import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/state/sleep_timer.dart';
import 'package:fathom/widgets/sleep_timer_sheet.dart';

void main() {
  testWidgets('a timed stop winds down every open player as time runs out',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(sleepTimerProvider.notifier);
    final fades = <Duration>[];
    c.register((fade) async => fades.add(fade));
    c.register((fade) async => fades.add(fade));

    c.startTimed(const Duration(minutes: 1));
    expect(container.read(sleepTimerProvider).mode, SleepMode.timed);

    // The fade starts early, so silence lands right as the minute is up.
    await tester.pump(const Duration(seconds: 44));
    expect(fades, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(fades, hasLength(2));
    expect(fades.first, SleepTimerController.fade);
    expect(container.read(sleepTimerProvider).active, isFalse);
  });

  testWidgets('a closed player is no longer stopped', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(sleepTimerProvider.notifier);
    var calls = 0;
    final unregister = c.register((_) async => calls++);
    unregister();
    c.startTimed(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 6));
    expect(calls, 0);
  });

  test('"end of" stops exactly once, and cancel clears it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(sleepTimerProvider.notifier);
    expect(c.consumeEndOfItem(), isFalse);

    c.startEndOfItem();
    expect(c.stopsAtEndOfItem, isTrue);
    expect(c.consumeEndOfItem(), isTrue);
    expect(c.consumeEndOfItem(), isFalse);

    c.startEndOfItem();
    c.cancel();
    expect(c.consumeEndOfItem(), isFalse);
    expect(container.read(sleepTimerProvider).active, isFalse);
  });

  test('remaining time reads naturally', () {
    expect(sleepRemainingLabel(const Duration(minutes: 22, seconds: 1)), '23m');
    expect(sleepRemainingLabel(const Duration(minutes: 65)), '1h 5m');
    expect(sleepRemainingLabel(const Duration(seconds: 42)), '42s');
  });

  testWidgets('picking a time from the button starts the countdown',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SleepTimerButton(endOfItemLabel: 'End of Track')),
        ),
      ),
    ));
    await tester.tap(find.byType(SleepTimerButton));
    await tester.pumpAndSettle();
    expect(find.text('End of Track'), findsOneWidget);

    await tester.tap(find.text('30 Minutes'));
    await tester.pumpAndSettle();
    expect(find.text('30m'), findsOneWidget);

    // Reopening shows the countdown and a way to turn it off.
    await tester.tap(find.byType(SleepTimerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn Off'));
    await tester.pumpAndSettle();
    expect(find.text('30m'), findsNothing);
  });
}

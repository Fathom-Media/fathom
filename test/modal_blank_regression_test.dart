import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/theme/app_theme.dart';

/// Why modals rendered blank from the library and guide screens.
///
/// Those sheets ended with Row[TextButton, Spacer, FilledButton]. A Row hands
/// non-flex children unbounded width, and the button themes set
/// `minimumSize: Size.fromHeight(52)` — which is `Size(double.infinity, 52)`,
/// an infinite MINIMUM width. RenderFlex rejects it, the button never lays out,
/// and "RenderBox was not laid out" then cascades UP through the Row, the
/// Column, the sheet's Stack and its Material — so the sheet itself is never
/// laid out and paints nothing.
///
/// It explains the whole mystery: the builder still runs and the data still
/// loads (build succeeds, layout fails), swapping the bottom sheet for a Dialog
/// changed nothing (same content), useRootNavigator:true changed nothing (the
/// navigator was never involved), and the same sheets worked from the detail
/// screen, which has no bare button in a Row.
///
/// The fix is kInlineButtonStyle on any Filled/Outlined button inside a Row.
/// button_in_row_guard_test.dart keeps that from coming back.
void main() {
  Widget filterSheet({required bool withFix}) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.all(20), child: Text('Filters')),
            SwitchListTile(
                title: const Text('Unwatched only'),
                value: false,
                onChanged: (_) {}),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(onPressed: () {}, child: const Text('Clear all')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {},
                    style: withFix ? kInlineButtonStyle : null,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> open(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(const Color(0xFF7C4DFF)),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
                context: context, isScrollControlled: true, builder: (_) => body),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a bare themed button in a Row blanks the WHOLE sheet',
      (tester) async {
    await open(tester, filterSheet(withFix: false));
    expect(tester.takeException(), isNotNull);
    // The sheet's own surface is what matters. Individual children may have
    // laid out already; the sheet not laying out is what makes it invisible.
    expect(() => tester.getSize(find.byType(BottomSheet)), throwsA(anything),
        reason: 'the sheet was never laid out, so nothing painted: blank');
  });

  testWidgets('with kInlineButtonStyle the sheet lays out and shows',
      (tester) async {
    await open(tester, filterSheet(withFix: true));
    expect(tester.takeException(), isNull);
    final sheet = tester.getSize(find.byType(BottomSheet));
    expect(sheet.height, greaterThan(0));
    expect(sheet.width, greaterThan(0));
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });
}

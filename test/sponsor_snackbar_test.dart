import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The skip notice has to go away on its own.
///
/// Flutter defaults `persist` to `action != null` (snack_bar.dart:
/// `persist = persist ?? action != null`), so a SnackBar with an Undo button
/// silently becomes one that waits forever. Ours has Undo, so it must say
/// persist: false — and this is easy to lose in a refactor.
void main() {
  Future<bool> dismisses(WidgetTester tester, SnackBar bar) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(bar),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget, reason: 'it should show');
    await tester.pump(const Duration(seconds: 5)); // past the 4s duration
    await tester.pump(const Duration(seconds: 1)); // exit animation
    return find.byType(SnackBar).evaluate().isEmpty;
  }

  testWidgets('the skip notice self-dismisses despite having Undo',
      (tester) async {
    final ours = SnackBar(
      duration: const Duration(seconds: 4),
      persist: false,
      content: const Text('Skipped sponsor (74s)'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    expect(await dismisses(tester, ours), isTrue,
        reason: 'a skip notice that never leaves is worse than none');
  });

  testWidgets('without persist:false the same notice never leaves',
      (tester) async {
    // Documents the trap: this is what the bug looked like.
    final trap = SnackBar(
      duration: const Duration(seconds: 4),
      content: const Text('Skipped sponsor (74s)'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    expect(await dismisses(tester, trap), isFalse);
  });
}

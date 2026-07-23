import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/theme/app_theme.dart';

/// Where does the app's button theme actually explode, and where is it fine?
/// Size.fromHeight(52) == Size(double.infinity, 52): an infinite MINIMUM width.
/// Any parent that offers unbounded width makes the button demand infinity,
/// layout throws, and the framework skips painting it entirely.
void main() {
  final theme = AppTheme.dark(const Color(0xFF7C4DFF));

  Future<String> probe(WidgetTester tester, String label, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(body: child),
    ));
    await tester.pump();
    final ex = tester.takeException();
    if (ex != null) return 'THROWS';
    final f = find.byType(FilledButton);
    if (!tester.any(f)) return 'not found';
    return '${tester.getSize(f).width.toStringAsFixed(0)}px wide';
  }

  testWidgets('AlertDialog actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: AlertDialog(
          title: const Text('T'),
          content: const Text('C'),
          actions: [
            TextButton(onPressed: () {}, child: const Text('Cancel')),
            FilledButton(onPressed: () {}, child: const Text('OK')),
          ],
        ),
      ),
    ));
    await tester.pump();
    final ex = tester.takeException();
    // ignore: avoid_print
    print('CONTEXT ${'AlertDialog actions'.padRight(28)} -> '
        '${ex != null ? 'THROWS' : '${tester.getSize(find.byType(FilledButton)).width.toStringAsFixed(0)}px wide'}');
  });

  testWidgets('the theme only breaks in unbounded-width parents',
      (tester) async {
    final btn = FilledButton(onPressed: () {}, child: const Text('X'));

    // Unbounded width: the infinite minimum is taken literally and layout dies.
    expect(await probe(tester, 'row', Row(children: [btn])), 'THROWS');
    expect(
        await probe(tester, 'hscroll',
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: btn)),
        'THROWS');

    // Bounded width: the infinity clamps to the bound, which is what makes the
    // app's form buttons span their column. Changing the theme would restyle
    // all of these, which is why the fix is per-call-site.
    expect(await probe(tester, 'col', Column(children: [btn])), '800px wide');
    expect(await probe(tester, 'lv', ListView(children: [btn])), '800px wide');
    expect(await probe(tester, 'center', Center(child: btn)), '800px wide');
    expect(await probe(tester, 're', Row(children: [Expanded(child: btn)])),
        '800px wide');
    expect(await probe(tester, 'sb', SizedBox(width: 200, child: btn)),
        '200px wide');
  });
}

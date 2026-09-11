import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/widgets/media_cards.dart';
import 'package:fathom/widgets/spin_wheel.dart';

Widget _app(Widget child) => ProviderScope(
      overrides: [deviceIdProvider.overrideWithValue('test-device')],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  setUpAll(MediaKit.ensureInitialized);

  testWidgets('a poster card is one button that says its title and year',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(PosterCard(
      item: const BaseItemDto(id: 'm1', name: 'Arrival', productionYear: 2016),
      onTap: () {},
      contextActions: false,
    )));
    await tester.pump();
    expect(
      tester.getSemantics(find.text('Arrival')),
      containsSemantics(label: 'Arrival\n2016', isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('the wheel names itself and its titles, and spins on activate',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(SpinWheel(
      items: const [
        BaseItemDto(id: 'a', name: 'Arrival'),
        BaseItemDto(id: 'b', name: 'Heat'),
      ],
      size: 300,
      onLanded: (_) {},
    )));
    await tester.pump();
    expect(
      tester.getSemantics(find.byType(SpinWheel)),
      containsSemantics(
        label: 'Movie Night Wheel with 2 titles: Arrival, Heat',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  test('every icon button has a tooltip (its screen-reader label)', () {
    // An icon-only button with no tooltip is announced as just "button", so a
    // screen-reader user can't tell play from skip from close. The tooltip is
    // both the hover hint and the spoken label.
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/generated/')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\bIconButton(?:\.\w+)?\(').allMatches(src)) {
        var i = m.end, depth = 1;
        while (depth > 0 && i < src.length) {
          final c = src[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        if (!src.substring(m.start, i).contains('tooltip:')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          missing.add('${f.path}:$line');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'IconButtons without a tooltip:\n${missing.join('\n')}');
  });
}

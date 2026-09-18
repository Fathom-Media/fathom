import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/widgets/media_cards.dart';

// A title's extras are its bonus material: behind the scenes, deleted scenes,
// interviews, and trailer files held on the server (which are a different thing
// from the RemoteTrailers URL the detail page's trailer button opens).
BaseItemDto _extra({String? type, int? ticks}) => BaseItemDto(
      id: 'x1',
      name: 'Deleted: the ending',
      type: 'Video',
      extraType: type,
      runTimeTicks: ticks,
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
  test('ExtraType comes off the item JSON', () {
    final item = BaseItemDto.fromJson(const {
      'Id': 'x1',
      'Name': 'Behind the scenes',
      'ExtraType': 'BehindTheScenes',
    });
    expect(item.extraType, 'BehindTheScenes');
  });

  testWidgets('an extra card names its kind and runtime', (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      height: 220,
      child: ExtraCard(
        item: _extra(type: 'DeletedScene', ticks: 4 * 600000000),
        kind: 'Deleted Scene',
        onTap: () {},
      ),
    )));
    await tester.pump();

    expect(find.text('Deleted: the ending'), findsOneWidget);
    expect(find.textContaining('Deleted Scene'), findsOneWidget);
    expect(find.textContaining('4m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown kind just shows the runtime', (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      height: 220,
      child: ExtraCard(
        item: _extra(type: 'SomethingNew', ticks: 90 * 600000000),
        onTap: () {},
      ),
    )));
    await tester.pump();

    expect(find.textContaining('SomethingNew'), findsNothing,
        reason: 'never show the raw enum name');
    expect(tester.takeException(), isNull);
  });
}

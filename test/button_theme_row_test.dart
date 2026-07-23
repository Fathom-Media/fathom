import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/subscribe_button.dart';
import 'package:fathom/models/youtube_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('a themed FilledButton in a Row demands infinite width',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(const Color(0xFF7C4DFF)),
      home: Scaffold(
        body: Row(children: [FilledButton(onPressed: () {}, child: const Text('X'))]),
      ),
    ));
    // Documents the landmine: Size.fromHeight == Size(infinity, h).
    expect(tester.takeException(), isNotNull,
        reason: 'the global theme forces an infinite minimum width');
  });

  testWidgets('SubscribeButton lays out and paints inside a Row',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(const Color(0xFF7C4DFF)),
        home: Scaffold(
          body: Row(children: [
            const Text('Channel name'),
            SubscribeButton(
                channel: const YoutubeChannel(id: 'a', title: 'A', logoUrl: '')),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Subscribe'), findsOneWidget);
    final size = tester.getSize(find.byType(SubscribeButton));
    expect(size.width.isFinite, isTrue);
    expect(size.width, lessThan(400));
  });
}

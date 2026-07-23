import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Why the watch page swaps videos in place instead of calling pushReplacement.
///
/// Two separate faults made the channel row look dead and then broke Back.
///
/// The route shape: /youtube/watch and /youtube/channel both sit on the ROOT
/// navigator, while /youtube lives in the ShellRoute. The channel route used to
/// be a shell route, so pushing it from the root-level watch page inserted its
/// page into the shell's navigator — underneath the video still on screen.
///
/// On top of that, hopping between related videos used to pushReplacement the
/// same /youtube/watch path each time. That mints colliding page keys, and the
/// damage surfaces later: the next push is rejected outright and pops throw in
/// go_router's _handlePopPage, breaking Back for the rest of the session. The
/// watch page now swaps video in place and never re-navigates.
GoRouter buildRouter() => GoRouter(
      initialLocation: '/youtube',
      routes: [
        GoRoute(
          path: '/youtube/watch',
          builder: (context, state) => Scaffold(
            body: Column(children: [
              const Text('WATCH'),
              GestureDetector(
                onTap: () => context.pushReplacement('/youtube/watch'),
                child: const Text('NEXT VIDEO'),
              ),
              GestureDetector(
                onTap: () => context.push('/youtube/channel'),
                child: const Text('CHANNEL ROW'),
              ),
            ]),
          ),
        ),
        GoRoute(
          path: '/youtube/channel',
          builder: (context, state) => const Text('CHANNEL PAGE'),
        ),
        ShellRoute(
          builder: (context, state, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/youtube',
              builder: (context, state) => Scaffold(
                body: GestureDetector(
                  onTap: () => context.push('/youtube/watch'),
                  child: const Text('OPEN WATCH'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

Future<void> openWatch(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN WATCH'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the watch page is pushed once: channel opens and Back pops',
      (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await openWatch(tester);

    // The real page swaps video in place, so no matter how many videos are
    // watched the navigator stack still looks exactly like this.
    await tester.tap(find.text('CHANNEL ROW'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CHANNEL PAGE'), findsOneWidget);

    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('WATCH'), findsOneWidget);
  });

  test('the watch page never re-navigates to itself', () {
    // pushReplacement onto the same path repeatedly is what produced
    // 'Null check operator used on a null value' in go_router's
    // _handlePopPage, followed by a cascade of !_debugLocked assertions —
    // Back stayed broken for the rest of the session. The page swaps its
    // video in place instead, which also keeps the back stack shallow (the
    // reason pushReplacement was there to begin with).
    final code = File('lib/screens/youtube_watch_screen.dart')
        .readAsLinesSync()
        // Comments explain the trap; only real calls matter.
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('pushReplacement('), isFalse,
        reason: 'swap _videoId in setState instead of re-navigating');
  });
}

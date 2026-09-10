import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// _GroupTile in syncplay_screen.dart is file-private, so this reconstructs
// its exact Row shape (icon, title/subtitle column, trailing Join label,
// optional chevron) rather than importing it directly. Pins the layout that
// replaced a real overflow bug: a long group name plus a long participant
// list (or a longer translation of "In a group") overflowed a Spacer-based
// row that let the title column claim up to 520px regardless of the actual
// screen width. See lib/screens/syncplay_screen.dart's _GroupTile.
Widget buildGroupTileRow({
  required String groupName,
  required String subtitle,
  required String joinLabel,
  required bool canJoin,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 68,
              color: Colors.grey.shade800,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(groupName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, height: 1.25)),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 12.5, height: 1.25)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      joinLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (canJoin) const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('GroupTile row: short content lays out cleanly', (tester) async {
    await tester.pumpWidget(buildGroupTileRow(
      groupName: 'Living Room',
      subtitle: 'Alice, Bob',
      joinLabel: 'Join',
      canJoin: true,
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'GroupTile row: long group name, many participants, and a long '
      'translated label never overflow, even on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildGroupTileRow(
      groupName: 'Family Movie Night Watch Party Group',
      subtitle:
          'Alice, Bob, Charlie, Dana, Evan, Fiona, Grace, Henry watching',
      // A stand-in for a longer translation of "In a group".
      joinLabel: 'Sie befinden sich bereits in einer anderen Gruppe',
      canJoin: false,
    ));
    expect(tester.takeException(), isNull);
    // The title column should still have real width, not have collapsed to
    // zero (Expanded inside a plain ListView.children item is the shape a
    // past attempt here reportedly broke; confirm it doesn't).
    final size = tester.getSize(
        find.text('Family Movie Night Watch Party Group'));
    expect(size.width, greaterThan(50));
  });
}

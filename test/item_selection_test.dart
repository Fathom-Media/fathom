import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/base_item.dart';
import 'package:fathom/widgets/item_selection.dart';

// Selection is a mode a grid enters from a card's own menu, so an ordinary tap
// keeps opening a title. These pin the behaviour the grids rely on.
BaseItemDto _item(String id) => BaseItemDto(id: id, name: 'Item $id');

void main() {
  test('a grid is not selecting until asked', () {
    final s = ItemSelection();
    expect(s.active, isFalse);
    expect(s.isEmpty, isTrue);
  });

  test('starting from a card ticks that card', () {
    final s = ItemSelection()..start(_item('a'));
    expect(s.active, isTrue);
    expect(s.contains('a'), isTrue);
    expect(s.length, 1);
  });

  test('tapping a ticked item unticks it, and the mode stays on', () {
    final s = ItemSelection()..start(_item('a'));
    s.toggle(_item('a'));
    expect(s.contains('a'), isFalse);
    expect(s.isEmpty, isTrue);
    expect(s.active, isTrue,
        reason: 'emptying the selection should not drop you out of the mode');
  });

  test('select all adds everything on screen, without duplicating', () {
    final all = [_item('a'), _item('b'), _item('c')];
    final s = ItemSelection()..start(all.first);
    s.selectAll(all);
    expect(s.length, 3);
    s.selectAll(all);
    expect(s.length, 3);
  });

  test('leaving the mode clears what was picked', () {
    final s = ItemSelection()..start(_item('a'));
    s.toggle(_item('b'));
    s.stop();
    expect(s.active, isFalse);
    expect(s.isEmpty, isTrue);
  });

  test('it notifies on every change, so the grid repaints', () {
    var notifications = 0;
    final s = ItemSelection()..addListener(() => notifications++);
    s.start(_item('a'));
    s.toggle(_item('b'));
    s.selectAll([_item('c')]);
    s.stop();
    expect(notifications, 4);
  });
}

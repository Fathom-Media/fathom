import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/library_providers.dart';

// Taken from a real library (2026-09-13): fifteen entries, eleven of them
// shorts from two cartoon series sampled a year earlier, each a minute or two
// in. The row is meant to answer "what am I in the middle of", and eleven
// near-identical entries bury the four things that actually answer it.
BaseItemDto _episode(String id, String seriesId, String name) => BaseItemDto(
      id: id,
      name: name,
      type: 'Episode',
      seriesId: seriesId,
      seriesName: seriesId,
    );

BaseItemDto _movie(String id, String name) =>
    BaseItemDto(id: id, name: name, type: 'Movie');

void main() {
  test('a series keeps only its most recent episode', () {
    final collapsed = collapseResumeBySeries([
      _episode('a', 'tom', 'The Brothers Carry-Mouse-Off'),
      _episode('b', 'tom', 'Tot Watchers'),
      _episode('c', 'tom', 'Little Quacker'),
    ]);
    expect(collapsed.map((e) => e.id), ['a'],
        reason: 'the server lists most recent first, so the first one wins');
  });

  test('films and one-offs are never collapsed', () {
    final collapsed = collapseResumeBySeries([
      _movie('inception', 'Inception'),
      _movie('heat', 'Heat'),
    ]);
    expect(collapsed.length, 2);
  });

  test('different series each keep an entry, in the order given', () {
    final collapsed = collapseResumeBySeries([
      _movie('inception', 'Inception'),
      _episode('csm', 'chainsaw', "Meowy's Whereabouts"),
      _episode('tz', 'twilight', 'Valley of the Shadow'),
      _episode('t1', 'tom', 'The Brothers Carry-Mouse-Off'),
      _episode('l1', 'looney', 'Baton Bunny'),
      _episode('l2', 'looney', "Sinkin' in the Bathtub"),
      _episode('t2', 'tom', 'Tot Watchers'),
      _episode('t3', 'tom', 'Little Quacker'),
      _episode('l3', 'looney', 'Hare Trigger'),
    ]);
    expect(collapsed.map((e) => e.id), ['inception', 'csm', 'tz', 't1', 'l1'],
        reason: 'nine entries from a real row become five');
  });

  test('an empty row stays empty', () {
    expect(collapseResumeBySeries(const []), isEmpty);
  });
}

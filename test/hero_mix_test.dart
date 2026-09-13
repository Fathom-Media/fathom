import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/library_providers.dart';

// The Home banner used to take eight items straight from the resume and Next
// Up lists. On a real library that led with a film from July and three
// year-old cartoon shorts, and never reached the show watched the night before.
BaseItemDto _show(String id, String series) =>
    BaseItemDto(id: id, name: id, type: 'Episode', seriesId: series);
BaseItemDto _film(String id) => BaseItemDto(id: id, name: id, type: 'Movie');

void main() {
  final watching = [
    _show('elr-16', 'raymond'),
    _show('lan-3', 'lanterns'),
    _show('ted', 'ted-lasso'),
    _show('hm', 'honeymooners'),
    _film('inception'),
  ];
  final added = [
    _film('new-a'),
    _film('new-b'),
    _film('new-c'),
    _film('new-d'),
    _film('new-e'),
    _film('new-f'),
  ];

  test('leads with what you are actually watching, most recent first', () {
    final hero = heroMix(watching: watching, added: added);
    expect(hero.take(3).map((e) => e.id), ['elr-16', 'lan-3', 'ted']);
  });

  test('then fills with what is new, instead of repeating the row below', () {
    final hero = heroMix(watching: watching, added: added);
    expect(hero.map((e) => e.id),
        ['elr-16', 'lan-3', 'ted', 'new-a', 'new-b', 'new-c']);
    expect(hero.length, 6);
  });

  test('with little new in the library, watching fills the rest', () {
    final hero = heroMix(watching: watching, added: [_film('only-new')]);
    expect(hero.map((e) => e.id),
        ['elr-16', 'lan-3', 'ted', 'only-new', 'hm', 'inception']);
  });

  test('never shows the same title twice', () {
    final hero = heroMix(
      watching: watching,
      added: [_film('inception'), ...added],
    );
    expect(hero.map((e) => e.id).where((id) => id == 'inception').length,
        lessThanOrEqualTo(1));
  });

  test('an empty library gives an empty banner', () {
    expect(heroMix(watching: const [], added: const []), isEmpty);
  });
}

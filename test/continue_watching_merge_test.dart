import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/base_item.dart';
import 'package:fathom/state/library_providers.dart';
import 'package:fathom/state/preferences.dart';

// Every date, title and order here is copied from a real Jellyfin 12.0 server
// (2026-09-13), where Continue Watching had become a shelf of year-old cartoon
// shorts and the show watched the night before was missing from it entirely.
DateTime _d(String iso) => DateTime.parse(iso);

// The afternoon these lists were read off the server.
final _now = _d('2026-09-13T12:00:00Z');

BaseItemDto _ep(String id, String series, String name, [String? played]) =>
    BaseItemDto(
      id: id,
      name: name,
      type: 'Episode',
      seriesId: series,
      seriesName: series,
      userData: UserItemData(
        lastPlayedDate: played == null ? null : _d(played),
        playbackPositionTicks: played == null ? 0 : 1,
      ),
    );

BaseItemDto _movie(String id, String name, String played) => BaseItemDto(
  id: id,
  name: name,
  type: 'Movie',
  userData: UserItemData(lastPlayedDate: _d(played), playbackPositionTicks: 1),
);

final _resume = [
  _movie('inception', 'Inception', '2026-07-26T02:06:00Z'),
  _ep('csm-e2', 'Chainsaw Man', "Meowy's Whereabouts", '2026-04-18T02:49:21Z'),
  _ep(
    'tz-valley',
    'The Twilight Zone',
    'Valley of the Shadow',
    '2025-09-07T15:25:23Z',
  ),
  _ep(
    'tj-brothers',
    'Tom and Jerry',
    'The Brothers Carry-Mouse-Off',
    '2025-08-08T04:04:30Z',
  ),
  _ep('lt-baton', 'New Looney Tunes', 'Baton Bunny', '2025-06-07T03:18:23Z'),
];

final _nextUp = [
  _ep('lan-3', 'Lanterns', 'Episode 3'),
  _ep('hm-23', 'The Honeymooners', 'Mama Loves Mambo'),
  _ep('sn-4', 'Spider-Noir', "A Mistake I'll Never Make Again"),
  _ep('bat-2', 'Batman', 'On Leather Wings'),
  _ep('lt-next', 'New Looney Tunes', 'From A to Z-Z-Z-Z'),
  _ep('nba', 'NBA Finals', 'Spurs at Knicks'),
  _ep('tz-s5e5', 'The Twilight Zone', 'The Last Night of a Jockey'),
  _ep('tj-feathered', 'Tom and Jerry', 'Fine Feathered Friend'),
  _ep('ted-s3e3', 'Ted Lasso', '4-5-1'),
  _ep('elr-16', 'Everybody Loves Raymond', 'Diamonds'),
  _ep('inv-6', 'INVINCIBLE', 'You Look Horrible'),
  _ep('csm-e5', 'Chainsaw Man', 'Gun Devil'),
  _ep('chad', 'Chad Powers', '7th Quarter'),
  _ep('aa', 'All American', 'Best Friends'),
  _ep('ind', 'Industry', 'Induction'),
];

// The most recent finished episode of each show, as the server reported them.
final _finished = [
  _ep(
    'elr-13',
    'Everybody Loves Raymond',
    "Debra's Sick",
    '2026-09-13T02:01:08Z',
  ),
  _ep('lan-2', 'Lanterns', 'Episode 2', '2026-08-24T01:49:05Z'),
  _ep('ted-s1e4', 'Ted Lasso', 'For the Children', '2026-08-22T02:11:45Z'),
  _ep(
    'hm-22',
    'The Honeymooners',
    'Here Comes the Bride',
    '2026-08-08T15:15:15Z',
  ),
  _ep('sn-3', 'Spider-Noir', 'Double Cross', '2026-08-07T14:34:54Z'),
  _ep('rm', 'Rick and Morty', 'Field of Dreams', '2026-07-28T02:48:36Z'),
  _ep('bat-1', 'Batman', 'The Cat and the Claw', '2026-07-25T21:39:48Z'),
  _ep('lt-mice', 'New Looney Tunes', 'Mice', '2026-07-19T22:02:18Z'),
  _ep('nba-g', 'NBA Finals', 'Knicks at Spurs', '2026-06-14T07:10:32Z'),
  _ep('csm-e1', 'Chainsaw Man', 'Dog & Chainsaw', '2026-03-28T02:51:52Z'),
  _ep('tz-s3e29', 'The Twilight Zone', "Four O'Clock", '2026-03-20T11:43:04Z'),
  _ep('inv-3', 'INVINCIBLE', 'I Gotta Get Some Air', '2026-03-20T01:40:50Z'),
];

void main() {
  final merged = mergeContinueWatching(
    resume: _resume,
    nextUp: _nextUp,
    finished: _finished,
    now: _now,
  );
  final ids = merged.map((e) => e.id).toList();

  test('the show watched last night leads the row', () {
    expect(
      ids.first,
      'elr-16',
      reason:
          'Raymond was absent from Continue Watching and ninth in Next '
          'Up, despite being watched the night before',
    );
  });

  test('the whole row follows actual viewing, newest first', () {
    expect(ids, [
      'elr-16', // Raymond, finished an episode 13 Sep
      'lan-3', // Lanterns, 24 Aug
      'ted-s3e3', // Ted Lasso, 22 Aug
      'hm-23', // The Honeymooners, 8 Aug
      'sn-4', // Spider-Noir, 7 Aug
      'inception', // stopped part-way, 26 Jul
      'bat-2', // Batman, 25 Jul
      'lt-next', // Looney Tunes, 19 Jul
      'nba', // NBA Finals, 14 Jun
      'csm-e2', // Chainsaw Man, stopped part-way 18 Apr
      'tz-s5e5', // Twilight Zone, 20 Mar (later that day than INVINCIBLE)
      'inv-6', // INVINCIBLE, 20 Mar
      'tj-brothers', // Tom and Jerry, stopped part-way Aug 2025
    ]);
  });

  test('a show that is only waiting, with no recent viewing, stays out', () {
    // Chad Powers, All American and Industry are in Next Up but absent from
    // the recent history, so in this row they would only be clutter.
    expect(ids, isNot(contains('chad')));
    expect(ids, isNot(contains('aa')));
    expect(ids, isNot(contains('ind')));
  });

  test('something part-way through stays even with no finished history', () {
    // Tom and Jerry: part-way through a short, nothing finished recently. It
    // can be removed with the Remove action, so it belongs here.
    expect(ids, contains('tj-brothers'));
  });

  test('a stale half-watched episode gives way to where you actually are', () {
    // Twilight Zone: left "Valley of the Shadow" part-way in September 2025,
    // then finished Season 3 in March 2026. The row shows the next episode.
    expect(ids, contains('tz-s5e5'));
    expect(ids, isNot(contains('tz-valley')));
    // Looney Tunes: a short part-way from 2025, others finished July 2026.
    expect(ids, contains('lt-next'));
    expect(ids, isNot(contains('lt-baton')));
  });

  test('a half-watched episode newer than the last finished one stays', () {
    // Chainsaw Man: finished E1 on 28 Mar, then stopped in E2 on 18 Apr.
    expect(ids, contains('csm-e2'));
    expect(ids, isNot(contains('csm-e5')));
  });

  test('each show appears once, and films stay whole', () {
    expect(ids.toSet().length, ids.length);
    expect(ids, contains('inception'));
    expect(merged.where((e) => e.seriesId == 'Tom and Jerry').length, 1);
  });

  test('a show you only ever finished, with nothing waiting, is not added', () {
    // Rick and Morty appears in finished episodes but has no next episode and
    // nothing in progress: it does not belong in this row.
    expect(merged.where((e) => e.seriesId == 'Rick and Morty'), isEmpty);
  });

  group('Remove', () {
    // What the row looks like after Remove on Chainsaw Man's half-watched E2:
    // the resume point is cleared on the server, so E2 drops out of the resume
    // list. Before dismissals the show came straight back as E5, and Remove
    // appeared to do nothing.
    final resumeAfterClear = _resume.where((e) => e.id != 'csm-e2').toList();

    test('clearing the resume point alone brings the show back', () {
      final after = mergeContinueWatching(
        resume: resumeAfterClear,
        nextUp: _nextUp,
        finished: _finished,
        now: _now,
      );
      expect(after.map((e) => e.id), contains('csm-e5'));
    });

    test('a removed show stays off the row', () {
      final after = mergeContinueWatching(
        resume: resumeAfterClear,
        nextUp: _nextUp,
        finished: _finished,
        dismissed: {'Chainsaw Man': _d('2026-09-13T12:00:00Z')},
        now: _now,
      );
      final afterIds = after.map((e) => e.id).toList();
      expect(afterIds, isNot(contains('csm-e2')));
      expect(afterIds, isNot(contains('csm-e5')));
      // Only that one show goes: everything else is untouched and in order.
      expect(afterIds, ids.where((id) => id != 'csm-e2').toList());
    });

    test('a waiting episode can be removed too', () {
      final after = mergeContinueWatching(
        resume: _resume,
        nextUp: _nextUp,
        finished: _finished,
        dismissed: {'Lanterns': _d('2026-09-13T12:00:00Z')},
        now: _now,
      );
      expect(after.map((e) => e.id), isNot(contains('lan-3')));
      expect(after.length, merged.length - 1);
    });

    test('a removed film stays off the row', () {
      final after = mergeContinueWatching(
        resume: _resume,
        nextUp: _nextUp,
        finished: _finished,
        dismissed: {'inception': _d('2026-09-13T12:00:00Z')},
        now: _now,
      );
      expect(after.map((e) => e.id), isNot(contains('inception')));
    });

    test('watching the show again brings it back', () {
      final finishedLater = [
        _ep('csm-e5', 'Chainsaw Man', 'Gun Devil', '2026-09-14T02:00:00Z'),
        ..._finished,
      ];
      final after = mergeContinueWatching(
        resume: resumeAfterClear,
        nextUp: [
          for (final e in _nextUp)
            if (e.id == 'csm-e5')
              _ep('csm-e6', 'Chainsaw Man', 'Kill Denji')
            else
              e,
        ],
        finished: finishedLater,
        dismissed: {'Chainsaw Man': _d('2026-09-13T12:00:00Z')},
        now: _now,
      );
      expect(after.first.id, 'csm-e6');
    });

    test('starting the removed film again brings it back', () {
      final after = mergeContinueWatching(
        resume: [
          _movie('inception', 'Inception', '2026-09-14T02:00:00Z'),
          ..._resume.skip(1),
        ],
        nextUp: _nextUp,
        finished: _finished,
        dismissed: {'inception': _d('2026-09-13T12:00:00Z')},
        now: _now,
      );
      expect(after.first.id, 'inception');
    });
  });

  test('removals survive a restart, per account', () {
    const prefs = Prefs(
      continueWatchingDismissed: {
        'user-a|Chainsaw Man': '2026-09-13T12:00:00.000Z',
      },
    );
    final back = Prefs.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(prefs.toJson()))),
    );
    expect(back.continueWatchingDismissed, prefs.continueWatchingDismissed);
    expect(Prefs.fromJson(const {}).continueWatchingDismissed, isEmpty);
  });

  group('New episodes', () {
    // Ted Lasso on the same server: Season 4 arrives weekly, the day after it
    // airs, and S4E6 was watched on 13 Sep. Here S4E7 turns up three days
    // later, while the rest of the row stays as it was.
    final now = _d('2026-09-16T12:00:00Z');
    BaseItemDto arrival(
      String id,
      String series,
      String name,
      String created,
    ) => BaseItemDto(
      id: id,
      name: name,
      type: 'Episode',
      seriesId: series,
      seriesName: series,
      dateCreated: _d(created),
    );
    final tedFinished = [
      _ep(
        'ted-s4e6',
        'Ted Lasso',
        "Don't Jump Around Much Anymore",
        '2026-09-13T15:50:02Z',
      ),
      ..._finished.where((e) => e.seriesId != 'Ted Lasso'),
    ];

    test('a new episode of a show you were caught up on goes to the front', () {
      final row = mergeContinueWatching(
        resume: _resume,
        nextUp: [
          arrival('ted-s4e7', 'Ted Lasso', 'Episode 7', '2026-09-16T01:14:00Z'),
          ..._nextUp.where((e) => e.seriesId != 'Ted Lasso'),
        ],
        finished: tedFinished,
        now: now,
      );
      expect(row.first.id, 'ted-s4e7');
    });

    test('it goes to the front even if you finished the show months ago', () {
      final row = mergeContinueWatching(
        resume: _resume,
        nextUp: [
          arrival('ted-s4e1', 'Ted Lasso', 'Home', '2026-09-15T15:03:23Z'),
          ..._nextUp.where((e) => e.seriesId != 'Ted Lasso'),
        ],
        finished: [
          _ep(
            'ted-s3e12',
            'Ted Lasso',
            'So Long, Farewell',
            '2026-03-02T02:00:00Z',
          ),
          ..._finished.where((e) => e.seriesId != 'Ted Lasso'),
        ],
        now: now,
      );
      expect(row.first.id, 'ted-s4e1');
    });

    test('the next episode of a show you drifted away from gets no boost', () {
      // Already in the library when you last watched, so nothing new to you.
      final row = mergeContinueWatching(
        resume: _resume,
        nextUp: [
          arrival(
            'csm-e5',
            'Chainsaw Man',
            'Gun Devil',
            '2026-03-29T01:11:15Z',
          ),
          ..._nextUp.where((e) => e.seriesId != 'Chainsaw Man'),
        ],
        finished: _finished,
        now: now,
      );
      expect(row.map((e) => e.id), ids);
    });

    test('a new show you never watched is not added', () {
      // Chad Powers S2E1 arrived on 3 Sep, but with no viewing history for the
      // show it stays in the Next Up row only.
      final row = mergeContinueWatching(
        resume: _resume,
        nextUp: [
          arrival('chad', 'Chad Powers', '7th Quarter', '2026-09-03T04:15:06Z'),
          ..._nextUp.where((e) => e.seriesId != 'Chad Powers'),
        ],
        finished: _finished,
        now: now,
      );
      expect(row.map((e) => e.id), isNot(contains('chad')));
    });

    test('an arrival older than the window does not jump the queue', () {
      final row = mergeContinueWatching(
        resume: _resume,
        nextUp: [
          arrival('ted-s4e1', 'Ted Lasso', 'Home', '2026-08-08T15:03:23Z'),
          ..._nextUp.where((e) => e.seriesId != 'Ted Lasso'),
        ],
        finished: [
          _ep(
            'ted-s3e12',
            'Ted Lasso',
            'So Long, Farewell',
            '2026-03-02T02:00:00Z',
          ),
          ..._finished.where((e) => e.seriesId != 'Ted Lasso'),
        ],
        now: now,
      );
      expect(row.first.id, 'elr-16');
      expect(row.last.id, 'tj-brothers');
      expect(row.map((e) => e.id), contains('ted-s4e1'));
    });

    test('a removed show comes back when a new episode arrives', () {
      final row = mergeContinueWatching(
        resume: _resume,
        nextUp: [
          arrival('ted-s4e7', 'Ted Lasso', 'Episode 7', '2026-09-16T01:14:00Z'),
          ..._nextUp.where((e) => e.seriesId != 'Ted Lasso'),
        ],
        finished: tedFinished,
        dismissed: {'Ted Lasso': _d('2026-09-14T00:00:00Z')},
        now: now,
      );
      expect(row.first.id, 'ted-s4e7');
    });
  });

  test('a show left waiting for over a year drops off', () {
    final row = mergeContinueWatching(
      resume: _resume,
      nextUp: _nextUp,
      finished: _finished,
      now: _d('2027-03-25T00:00:00Z'),
    );
    final rowIds = row.map((e) => e.id);
    // INVINCIBLE and The Twilight Zone were last watched on 20 Mar 2026.
    expect(rowIds, isNot(contains('inv-6')));
    expect(rowIds, isNot(contains('tz-s5e5')));
    // Chainsaw Man's half-watched episode stays: part-way through is still
    // part-way through, and Remove takes it off.
    expect(rowIds, contains('csm-e2'));
  });
}

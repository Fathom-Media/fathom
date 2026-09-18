import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/youtube_innertube.dart';

// Shaped exactly like a real /next response (video FIdOdiUQ91Y, 2026-09-14),
// trimmed to what the parse reads. youtube.com showed 42 chapters for it; the
// app showed none, because it only looked in the batch-update markers, which by
// then held nothing but the "most replayed" heatmap.
Map<String, dynamic> _response({
  List<Map<String, dynamic>> markersMap = const [],
}) => {
  'playerOverlays': {
    'playerOverlayRenderer': {
      'decoratedPlayerBarRenderer': {
        'decoratedPlayerBarRenderer': {
          'playerBar': {
            'multiMarkersPlayerBarRenderer': {'markersMap': markersMap},
          },
        },
      },
    },
  },
  'frameworkUpdates': {
    'entityBatchUpdate': {
      'mutations': [
        {
          'payload': {
            'macroMarkersListEntity': {
              'markersList': {
                'markerType': 'MARKER_TYPE_HEATMAP',
                'markers': [
                  for (var i = 0; i < 100; i++)
                    {'startMillis': '${i * 37000}', 'durationMillis': '37000'},
                ],
              },
            },
          },
        },
      ],
    },
  },
};

Map<String, dynamic> _chapter(String title, int ms) => {
  'chapterRenderer': {
    'title': {'simpleText': title},
    'timeRangeStartMillis': ms,
  },
};

void main() {
  final yt = YoutubeInnerTube();

  test('reads chapters from the player bar', () {
    final chapters = yt.chaptersFrom(
      _response(
        markersMap: [
          {
            'key': 'DESCRIPTION_CHAPTERS',
            'value': {
              'chapters': [
                _chapter('Why Tim Left the U.S.', 0),
                _chapter('How Life in Kenya Transformed Him', 63000),
                _chapter('The 4 Bedroom Mansion', 96000),
              ],
            },
          },
        ],
      ),
    );
    expect(chapters.map((c) => c.title), [
      'Why Tim Left the U.S.',
      'How Life in Kenya Transformed Him',
      'The 4 Bedroom Mansion',
    ]);
    expect(chapters[1].start, const Duration(seconds: 63));
  });

  test('the creator\'s chapters win over generated ones', () {
    final chapters = yt.chaptersFrom(
      _response(
        markersMap: [
          {
            'key': 'AUTO_CHAPTERS',
            'value': {
              'chapters': [_chapter('Generated', 0)],
            },
          },
          {
            'key': 'DESCRIPTION_CHAPTERS',
            'value': {
              'chapters': [_chapter('Written by the creator', 0)],
            },
          },
        ],
      ),
    );
    expect(chapters.single.title, 'Written by the creator');
  });

  test('generated chapters are used when there are no others', () {
    final chapters = yt.chaptersFrom(
      _response(
        markersMap: [
          {
            'key': 'AUTO_CHAPTERS',
            'value': {
              'chapters': [_chapter('Intro', 0), _chapter('Setup', 45000)],
            },
          },
        ],
      ),
    );
    expect(chapters.length, 2);
  });

  test('the heatmap is never mistaken for chapters', () {
    expect(yt.chaptersFrom(_response()), isEmpty);
  });
}

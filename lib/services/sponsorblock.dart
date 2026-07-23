import 'dart:convert';

import 'package:dio/dio.dart';

/// A kind of segment SponsorBlock knows about.
///
/// Each is toggled separately, because they're not the same thing: skipping a
/// paid ad read is uncontroversial, skipping the creator's own outro is a
/// preference, and skipping "filler" is a matter of taste.
enum SponsorCategory {
  sponsor('sponsor', 'Sponsor', 'Paid promotion or a paid ad read'),
  selfpromo('selfpromo', 'Self-Promotion', "The creator's own merch, Patreon or plugs"),
  interaction('interaction', 'Interaction Reminder', '"Like and subscribe"'),
  intro('intro', 'Intro', 'Intermission or intro animation'),
  outro('outro', 'Outro', 'Endcards and credits'),
  preview('preview', 'Preview / Recap', 'A recap, or a preview of what is coming'),
  filler('filler', 'Filler', 'Tangents and jokes that add no information'),
  musicOfftopic('music_offtopic', 'Non-Music', 'Non-music sections of a music video');

  const SponsorCategory(this.id, this.label, this.description);

  /// The value SponsorBlock uses on the wire.
  final String id;
  final String label;
  final String description;

  static SponsorCategory? fromId(String id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// A stretch of a video SponsorBlock says is skippable.
class SponsorSegment {
  final SponsorCategory category;
  final Duration start;
  final Duration end;

  /// Identifies the submission. Used to skip each segment only once.
  final String uuid;

  /// Community score. Negative means people disagree it's really there.
  final int votes;

  const SponsorSegment({
    required this.category,
    required this.start,
    required this.end,
    required this.uuid,
    this.votes = 0,
  });

  Duration get length => end - start;

  bool contains(Duration position) => position >= start && position < end;
}

/// The SponsorBlock API.
///
/// Skips segments inside the video that the creator put there — the "this video
/// is sponsored by…" read. Not YouTube's ads: those never reach us, because we
/// stream the video directly and never load YouTube's player.
///
/// The data is crowdsourced and released under CC BY-NC-SA 4.0, so this is
/// opt-in, attributed in Settings, and off by default.
class SponsorBlock {
  SponsorBlock({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  static const _endpoint = 'https://sponsor.ajay.app/api/skipSegments';

  /// Segments for [videoId] in [categories].
  ///
  /// An empty list is the normal answer for most videos, and the API says so
  /// with a 404 rather than an empty array — a video nobody has submitted for
  /// is not an error, so that isn't treated as one. Coverage is uneven: dense
  /// on tech and gaming, thin almost everywhere else.
  Future<List<SponsorSegment>> segments(
    String videoId, {
    Set<SponsorCategory> categories = const {},
  }) async {
    if (categories.isEmpty) return const [];
    try {
      final res = await _dio.get<List<dynamic>>(
        _endpoint,
        queryParameters: {
          'videoID': videoId,
          'categories': jsonEncode([for (final c in categories) c.id]),
        },
        options: Options(
          // 404 means "nothing submitted", which is the common case.
          validateStatus: (s) => s == 200 || s == 404,
        ),
      );
      if (res.statusCode == 404 || res.data == null) return const [];

      final out = <SponsorSegment>[];
      for (final e in res.data!.whereType<Map>()) {
        // Only 'skip' segments are stretches to jump over. poi_highlight marks
        // a point to jump TO, and treating it as a skip would leap past the
        // very thing it points at.
        if ('${e['actionType']}' != 'skip') continue;

        final category = SponsorCategory.fromId('${e['category']}');
        if (category == null) continue;

        final range = e['segment'];
        if (range is! List || range.length < 2) continue;
        final start = (range[0] as num).toDouble();
        final end = (range[1] as num).toDouble();
        // A zero-length or reversed segment would either do nothing or seek
        // backwards forever.
        if (end <= start) continue;

        out.add(SponsorSegment(
          category: category,
          start: Duration(milliseconds: (start * 1000).round()),
          end: Duration(milliseconds: (end * 1000).round()),
          uuid: '${e['UUID'] ?? ''}',
          votes: (e['votes'] as num?)?.toInt() ?? 0,
        ));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    } catch (_) {
      // Never let this break playback: it's an optional extra on a third-party
      // service, and a video plays perfectly well without it.
      return const [];
    }
  }
}

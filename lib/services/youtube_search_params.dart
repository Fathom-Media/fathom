import 'dart:convert';

/// What to search for.
enum YtSearchFilter { videos, channels, playlists }

/// How to order results.
enum YtSearchSort { relevance, uploadDate, viewCount, rating }

/// Only return things uploaded within this window.
enum YtUploadDate { any, lastHour, today, thisWeek, thisMonth, thisYear }

/// Only return videos of roughly this length.
enum YtDuration { any, under4Min, from4To20Min, over20Min }

/// Builds YouTube's search `params` value.
///
/// `params` is a protobuf, base64'd and percent-encoded. Most clients paste
/// magic constants ("EgIQAQ%3D%3D") for the handful of combinations they
/// support; encoding it properly means every combination works, including ones
/// nobody has a constant for.
///
/// The shape, confirmed by decoding the known-good constants:
///
///   outer {
///     1: sort_by  (varint)
///     2: filters {
///          1: upload_date (varint)
///          2: type        (varint)
///          3: duration    (varint)
///        }
///   }
///
/// e.g. videos-only is `12 02 10 01` = EgIQAQ==, and sort-by-upload-date plus
/// videos-only is `08 02 12 02 10 01` = CAISAhAB. Both round-trip through this
/// encoder, which is what the tests assert.
class YoutubeSearchParams {
  YoutubeSearchParams._();

  static String build({
    YtSearchFilter filter = YtSearchFilter.videos,
    YtSearchSort sort = YtSearchSort.relevance,
    YtUploadDate uploadDate = YtUploadDate.any,
    YtDuration duration = YtDuration.any,
  }) {
    final filters = <int>[
      ..._field(1, _uploadDateValue(uploadDate)),
      ..._field(2, _typeValue(filter)),
      // Duration only means anything for videos; YouTube ignores it otherwise,
      // and sending it with a channel search just makes a nonsense query.
      if (filter == YtSearchFilter.videos)
        ..._field(3, _durationValue(duration)),
    ];

    final outer = <int>[
      ..._field(1, _sortValue(sort)),
      if (filters.isNotEmpty) ...[
        0x12, // field 2, length-delimited
        filters.length,
        ...filters,
      ],
    ];

    return Uri.encodeComponent(base64Encode(outer));
  }

  /// A varint field, or nothing when the value is 0 — protobuf treats an absent
  /// field and a zero as the same thing, and YouTube's own constants omit them.
  static List<int> _field(int number, int value) {
    if (value == 0) return const [];
    return [(number << 3) | 0, ..._varint(value)];
  }

  static List<int> _varint(int value) {
    final out = <int>[];
    var v = value;
    while (v >= 0x80) {
      out.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return out;
  }

  static int _typeValue(YtSearchFilter f) => switch (f) {
        YtSearchFilter.videos => 1,
        YtSearchFilter.channels => 2,
        YtSearchFilter.playlists => 3,
      };

  static int _sortValue(YtSearchSort s) => switch (s) {
        YtSearchSort.relevance => 0, // the default, so it's omitted
        YtSearchSort.rating => 1,
        YtSearchSort.uploadDate => 2,
        YtSearchSort.viewCount => 3,
      };

  static int _uploadDateValue(YtUploadDate d) => switch (d) {
        YtUploadDate.any => 0,
        YtUploadDate.lastHour => 1,
        YtUploadDate.today => 2,
        YtUploadDate.thisWeek => 3,
        YtUploadDate.thisMonth => 4,
        YtUploadDate.thisYear => 5,
      };

  static int _durationValue(YtDuration d) => switch (d) {
        YtDuration.any => 0,
        YtDuration.under4Min => 1,
        YtDuration.over20Min => 2,
        YtDuration.from4To20Min => 3,
      };
}

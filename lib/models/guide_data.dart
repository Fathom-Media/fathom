import 'base_item.dart';

/// Everything the EPG guide grid needs: the channels, their programs keyed by
/// channel id, and the time window the grid spans.
///
/// The window grows on demand: the grid starts with a short span and extends its
/// [windowEnd] as the user scrolls toward the right edge, pulling in more EPG
/// until the server has no further programs ([atEnd]).
class GuideData {
  final List<BaseItemDto> channels;
  final Map<String, List<BaseItemDto>> programsByChannel;
  final DateTime windowStart;
  final DateTime windowEnd;

  /// A further chunk of guide data is being fetched right now.
  final bool loadingMore;

  /// The server returned no programs past [windowEnd]; there's nothing more to
  /// load, so the grid stops extending.
  final bool atEnd;

  const GuideData({
    required this.channels,
    required this.programsByChannel,
    required this.windowStart,
    required this.windowEnd,
    this.loadingMore = false,
    this.atEnd = false,
  });

  GuideData copyWith({
    Map<String, List<BaseItemDto>>? programsByChannel,
    DateTime? windowEnd,
    bool? loadingMore,
    bool? atEnd,
  }) =>
      GuideData(
        channels: channels,
        programsByChannel: programsByChannel ?? this.programsByChannel,
        windowStart: windowStart,
        windowEnd: windowEnd ?? this.windowEnd,
        loadingMore: loadingMore ?? this.loadingMore,
        atEnd: atEnd ?? this.atEnd,
      );
}

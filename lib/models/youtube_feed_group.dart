/// A named subset of your subscriptions, e.g. "Music", "News".
///
/// NewPipe calls these feed groups: with fifty subscriptions, one merged feed
/// is noise, and the useful question is "what's new from the handful I care
/// about right now". Stores channel ids only — the channels themselves live in
/// the subscriptions list, and duplicating them here would let the two drift.
class YoutubeFeedGroup {
  final String id;
  final String name;
  final List<String> channelIds;

  const YoutubeFeedGroup({
    required this.id,
    required this.name,
    this.channelIds = const [],
  });

  bool contains(String channelId) => channelIds.contains(channelId);

  String get countLabel => channelIds.length == 1
      ? '1 channel'
      : '${channelIds.length} channels';

  YoutubeFeedGroup copyWith({String? name, List<String>? channelIds}) =>
      YoutubeFeedGroup(
        id: id,
        name: name ?? this.name,
        channelIds: channelIds ?? this.channelIds,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'channelIds': channelIds};

  factory YoutubeFeedGroup.fromJson(Map<String, dynamic> j) => YoutubeFeedGroup(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        channelIds: [
          ...(j['channelIds'] as List? ?? const []).whereType<String>(),
        ],
      );
}

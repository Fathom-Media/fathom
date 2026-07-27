/// An internet-radio station: a live audio stream plus display metadata. Stored
/// locally (Fathom has no backend), or returned transiently from a radio-browser
/// directory search before the user adds it.
class RadioStation {
  final String id;
  final String name;
  final String url; // resolved stream URL
  final String? homepage;
  final String? favicon; // station logo URL
  final String? group; // user-assigned category
  final bool favorite;
  final String? tags; // comma-separated (from the directory)
  final String? country;

  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.homepage,
    this.favicon,
    this.group,
    this.favorite = false,
    this.tags,
    this.country,
  });

  RadioStation copyWith({
    String? name,
    String? url,
    String? homepage,
    String? favicon,
    Object? group = _unset, // sentinel so group can be set back to null
    bool? favorite,
    String? tags,
    String? country,
  }) =>
      RadioStation(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        homepage: homepage ?? this.homepage,
        favicon: favicon ?? this.favicon,
        group: group == _unset ? this.group : group as String?,
        favorite: favorite ?? this.favorite,
        tags: tags ?? this.tags,
        country: country ?? this.country,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'homepage': homepage,
        'favicon': favicon,
        'group': group,
        'favorite': favorite,
        'tags': tags,
        'country': country,
      };

  factory RadioStation.fromJson(Map<String, dynamic> j) => RadioStation(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        homepage: j['homepage'] as String?,
        favicon: j['favicon'] as String?,
        group: j['group'] as String?,
        favorite: j['favorite'] as bool? ?? false,
        tags: j['tags'] as String?,
        country: j['country'] as String?,
      );

  /// From a radio-browser.info /json/stations search result.
  factory RadioStation.fromRadioBrowser(Map<String, dynamic> j) => RadioStation(
        id: (j['stationuuid'] as String?) ?? (j['url_resolved'] as String? ?? ''),
        name: (j['name'] as String? ?? '').trim(),
        // url_resolved follows playlists/redirects to the real stream.
        url: (j['url_resolved'] as String?) ?? (j['url'] as String? ?? ''),
        homepage: j['homepage'] as String?,
        favicon: (j['favicon'] as String?)?.isNotEmpty == true
            ? j['favicon'] as String?
            : null,
        tags: j['tags'] as String?,
        country: j['country'] as String?,
      );
}

const _unset = Object();

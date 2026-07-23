/// Per-user playback state attached to an item.
class UserItemData {
  final double playedPercentage;
  final int playbackPositionTicks;
  final bool played;
  final bool isFavorite;
  final int unplayedItemCount; // unwatched children (series/season)

  const UserItemData({
    this.playedPercentage = 0,
    this.playbackPositionTicks = 0,
    this.played = false,
    this.isFavorite = false,
    this.unplayedItemCount = 0,
  });

  factory UserItemData.fromJson(Map<String, dynamic> json) => UserItemData(
        playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble() ?? 0,
        playbackPositionTicks:
            (json['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
        played: json['Played'] as bool? ?? false,
        isFavorite: json['IsFavorite'] as bool? ?? false,
        unplayedItemCount: (json['UnplayedItemCount'] as num?)?.toInt() ?? 0,
      );
}

/// A chapter marker within a video.
class Chapter {
  final int startTicks;
  final String? name;
  final String? imageTag;

  const Chapter({required this.startTicks, this.name, this.imageTag});

  Duration get start => Duration(microseconds: startTicks ~/ 10);

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        startTicks: (json['StartPositionTicks'] as num?)?.toInt() ?? 0,
        name: json['Name'] as String?,
        imageTag: json['ImageTag'] as String?,
      );
}

/// Trickplay (scrub-preview) tile geometry for one resolution of one item.
/// The server bakes evenly spaced thumbnails into sprite sheets; each sheet
/// holds [tileWidth] x [tileHeight] thumbs of [width] x [height] pixels.
class TrickplayInfo {
  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final int interval; // ms between thumbnails

  const TrickplayInfo({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.interval,
  });

  int get perTile => tileWidth * tileHeight;

  factory TrickplayInfo.fromJson(Map<String, dynamic> json) => TrickplayInfo(
        width: (json['Width'] as num?)?.toInt() ?? 0,
        height: (json['Height'] as num?)?.toInt() ?? 0,
        tileWidth: (json['TileWidth'] as num?)?.toInt() ?? 1,
        tileHeight: (json['TileHeight'] as num?)?.toInt() ?? 1,
        thumbnailCount: (json['ThumbnailCount'] as num?)?.toInt() ?? 0,
        interval: (json['Interval'] as num?)?.toInt() ?? 10000,
      );
}

/// A cast or crew member.
class Person {
  final String id;
  final String name;
  final String? role;
  final String? type; // Actor, Director, Writer, ...
  final String? primaryImageTag;

  const Person({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        role: json['Role'] as String?,
        type: json['Type'] as String?,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );
}

/// A lean projection of Jellyfin's BaseItemDto covering the fields the client
/// currently uses. Grows as new screens need more.
class BaseItemDto {
  final String id;
  final String name;
  final String? type; // Movie, Series, Episode, BoxSet, MusicAlbum, ...
  final String? collectionType; // movies, tvshows, music, livetv, ... (views)
  final String? primaryImageTag;
  final List<String> backdropImageTags;
  final String? seriesName;
  final String? seriesId;
  final int? productionYear;
  final int? indexNumber; // episode number
  final int? parentIndexNumber; // season number
  final int? runTimeTicks;
  final String? overview;
  final List<String> genres;
  final String? mediaType; // Video, Audio
  final bool isFolder;
  final String? officialRating;
  final double? communityRating; // IMDb-style, 0-10
  final double? criticRating; // Rotten Tomatoes critic score, 0-100
  final List<String> remoteTrailers; // trailer URLs (usually YouTube)
  final String? album;
  final String? albumId;
  final String? albumPrimaryImageTag;
  final String? albumArtist;
  final List<String> artists;
  final List<Person> artistItems; // artists with ids, for navigation
  final String? channelNumber;
  final String? channelId;
  final BaseItemDto? currentProgram;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? timerId; // set on a program that has a scheduled recording
  final String? seriesTimerId; // set when that recording is part of a series
  final List<Person> people;
  final List<Chapter> chapters;
  final UserItemData userData;
  final int? childCount; // e.g. number of items in a playlist / folder
  final String? playlistItemId; // per-entry id when listing playlist contents
  final String? logoImageTag; // the item's own Logo image (movies, series)
  final String? parentLogoImageTag; // series logo, present on episodes
  final String? episodeTitle; // Live TV program's episode/subtitle
  final String? seriesPrimaryImageTag; // series poster, present on episodes
  final TrickplayInfo? trickplayInfo; // best-resolution scrub-preview geometry
  final int? trickplayWidth; // resolution key for the trickplay tile URL
  final String? tmdbId; // TMDB id from ProviderIds, for external ratings

  const BaseItemDto({
    required this.id,
    required this.name,
    this.type,
    this.collectionType,
    this.primaryImageTag,
    this.backdropImageTags = const [],
    this.seriesName,
    this.seriesId,
    this.productionYear,
    this.indexNumber,
    this.parentIndexNumber,
    this.runTimeTicks,
    this.overview,
    this.genres = const [],
    this.mediaType,
    this.isFolder = false,
    this.officialRating,
    this.communityRating,
    this.criticRating,
    this.remoteTrailers = const [],
    this.album,
    this.albumId,
    this.albumPrimaryImageTag,
    this.albumArtist,
    this.artists = const [],
    this.artistItems = const [],
    this.channelNumber,
    this.channelId,
    this.currentProgram,
    this.startDate,
    this.endDate,
    this.timerId,
    this.seriesTimerId,
    this.people = const [],
    this.chapters = const [],
    this.userData = const UserItemData(),
    this.childCount,
    this.playlistItemId,
    this.logoImageTag,
    this.parentLogoImageTag,
    this.episodeTitle,
    this.seriesPrimaryImageTag,
    this.trickplayInfo,
    this.trickplayWidth,
    this.tmdbId,
  });

  /// Seerr media type for external ratings lookups: 'movie' or 'tv'.
  String? get seerrMediaType {
    if (isSeries || isEpisode) return 'tv';
    if (type == 'Movie') return 'movie';
    return null;
  }

  /// The first trailer URL (usually a YouTube link), if any.
  String? get trailerUrl => remoteTrailers.isNotEmpty ? remoteTrailers.first : null;

  bool get isEpisode => type == 'Episode';
  bool get isSeries => type == 'Series';
  bool get isAlbum => type == 'MusicAlbum';
  bool get isLiveChannel => type == 'TvChannel';
  bool get isAudio => mediaType == 'Audio' || type == 'Audio';

  /// A display artist line ("Artist A, Artist B" or the album artist).
  String? get artistLine {
    if (artists.isNotEmpty) return artists.join(', ');
    return albumArtist;
  }

  int get resumePositionTicks => userData.playbackPositionTicks;
  bool get canResume => resumePositionTicks > 0;

  /// How far through the item playback is, 0..1, or null when there's no saved
  /// position or the runtime is unknown. Drives the resume sliver on cards.
  double? get progressFraction {
    // No bar on finished items, matching Jellyfin web (a played item can still
    // carry a stale resume position).
    if (userData.played) return null;
    final rt = runTimeTicks;
    if (rt == null || rt <= 0 || resumePositionTicks <= 0) return null;
    return (resumePositionTicks / rt).clamp(0.0, 1.0);
  }

  // Title-logo art (a transparent PNG of the title's logo). For episodes the
  // logo lives on the parent series.
  String? get logoTag => logoImageTag ?? parentLogoImageTag;
  String? get logoItemId {
    if (logoImageTag != null) return id;
    if (parentLogoImageTag != null && seriesId != null) return seriesId;
    return null;
  }

  bool get hasLogo => logoTag != null && logoItemId != null;

  /// Runtime in whole minutes, or null when unknown.
  int? get runtimeMinutes =>
      runTimeTicks == null ? null : (runTimeTicks! / 600000000).round();

  /// Fraction (0..1) watched, for progress indicators.
  double get progress {
    if (userData.playedPercentage > 0) {
      return (userData.playedPercentage / 100).clamp(0, 1);
    }
    if (runTimeTicks != null && runTimeTicks! > 0) {
      return (userData.playbackPositionTicks / runTimeTicks!).clamp(0, 1);
    }
    return 0;
  }

  factory BaseItemDto.fromJson(Map<String, dynamic> json) {
    final imageTags =
        (json['ImageTags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trickplay = _parseTrickplay(json['Trickplay']);
    return BaseItemDto(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String?,
      collectionType: json['CollectionType'] as String?,
      primaryImageTag: imageTags['Primary'] as String?,
      backdropImageTags:
          (json['BackdropImageTags'] as List?)?.cast<String>() ?? const [],
      seriesName: json['SeriesName'] as String?,
      seriesId: json['SeriesId'] as String?,
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      overview: json['Overview'] as String?,
      genres: (json['Genres'] as List?)?.cast<String>() ?? const [],
      mediaType: json['MediaType'] as String?,
      isFolder: json['IsFolder'] as bool? ?? false,
      officialRating: json['OfficialRating'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      criticRating: (json['CriticRating'] as num?)?.toDouble(),
      remoteTrailers: (json['RemoteTrailers'] as List?)
              ?.whereType<Map>()
              .map((e) => e['Url'] as String?)
              .whereType<String>()
              .toList() ??
          const [],
      album: json['Album'] as String?,
      albumId: json['AlbumId'] as String?,
      albumPrimaryImageTag: json['AlbumPrimaryImageTag'] as String?,
      albumArtist: json['AlbumArtist'] as String?,
      artists: (json['Artists'] as List?)?.cast<String>() ?? const [],
      artistItems: (json['ArtistItems'] as List?)
              ?.whereType<Map>()
              .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      channelNumber: json['ChannelNumber'] as String?,
      channelId: json['ChannelId'] as String?,
      currentProgram: json['CurrentProgram'] is Map
          ? BaseItemDto.fromJson(
              Map<String, dynamic>.from(json['CurrentProgram'] as Map))
          : null,
      // Server sends UTC; keep these as local so every consumer formats the
      // viewer's local time (the guide, program details, recordings).
      startDate: DateTime.tryParse(json['StartDate'] as String? ?? '')?.toLocal(),
      endDate: DateTime.tryParse(json['EndDate'] as String? ?? '')?.toLocal(),
      timerId: json['TimerId'] as String?,
      seriesTimerId: json['SeriesTimerId'] as String?,
      people: (json['People'] as List?)
              ?.whereType<Map>()
              .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      chapters: (json['Chapters'] as List?)
              ?.whereType<Map>()
              .map((e) => Chapter.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      userData: UserItemData.fromJson(
          (json['UserData'] as Map?)?.cast<String, dynamic>() ?? const {}),
      childCount: (json['ChildCount'] as num?)?.toInt(),
      playlistItemId: json['PlaylistItemId'] as String?,
      logoImageTag: imageTags['Logo'] as String?,
      parentLogoImageTag: json['ParentLogoImageTag'] as String?,
      episodeTitle: json['EpisodeTitle'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
      trickplayInfo: trickplay?.$1,
      trickplayWidth: trickplay?.$2,
      tmdbId: (json['ProviderIds'] as Map?)?['Tmdb']?.toString(),
    );
  }

  /// Picks the highest-resolution trickplay tile set from the server's nested
  /// `Trickplay` map ({mediaSourceId: {widthKey: info}}), returning its geometry
  /// and the width key needed to build tile URLs.
  static (TrickplayInfo, int)? _parseTrickplay(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return null;
    // Merge all media sources; the width keys are what matter for the URL.
    final byWidth = <int, Map<String, dynamic>>{};
    for (final source in raw.values) {
      if (source is! Map) continue;
      source.forEach((k, v) {
        final w = int.tryParse('$k');
        if (w != null && v is Map) {
          byWidth[w] = Map<String, dynamic>.from(v);
        }
      });
    }
    if (byWidth.isEmpty) return null;
    final width = byWidth.keys.reduce((a, b) => a > b ? a : b);
    return (TrickplayInfo.fromJson(byWidth[width]!), width);
  }
}

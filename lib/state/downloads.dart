import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart' show Options, ResponseType;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../api/mdblist_client.dart';
import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../models/base_item.dart';
import '../models/session.dart';
import '../services/secure_http.dart';
import 'library_providers.dart';
import 'notifications_controller.dart';
import 'preferences.dart';
import 'providers.dart';
import 'seerr_providers.dart';
import 'session_controller.dart';

enum DownloadStatus { downloading, complete, failed }

/// The resolved rating inputs for a title (the same values the detail page feeds
/// to its score pills), cached at download time so the extra online ratings
/// (Rotten Tomatoes, Letterboxd, Metacritic, …) still show offline.
typedef CachedScores = ({
  int? rtCritic,
  int? rtAudience,
  double? imdb,
  double? community,
  int? letterboxd,
  int? metacritic,
  int? metacriticUser,
  int? trakt,
  int? rogerEbert,
  int? myAnimeList,
});

/// Merges native (Jellyfin/Seerr) and MDBList ratings into the pill inputs, the
/// same precedence the detail page uses (native first, MDBList as gap-fill).
CachedScores mergeCachedScores(
    {double? community, int? critic, ExternalRatings? ext, MdbRatings? mdb}) {
  return (
    rtCritic: ext?.rtCritic ?? critic ?? mdb?.rtCritic,
    rtAudience: ext?.rtAudience ?? mdb?.rtAudience,
    imdb: ext?.imdb ?? (mdb?.imdb != null ? mdb!.imdb! / 10 : null),
    community: community ?? (mdb?.tmdb != null ? mdb!.tmdb! / 10 : null),
    letterboxd: mdb?.letterboxd,
    metacritic: mdb?.metacritic,
    metacriticUser: mdb?.metacriticUser,
    trakt: mdb?.trakt,
    rogerEbert: mdb?.rogerEbert,
    myAnimeList: mdb?.myAnimeList,
  );
}

Map<String, dynamic> _scoresToJson(CachedScores s) => {
      if (s.rtCritic != null) 'rtCritic': s.rtCritic,
      if (s.rtAudience != null) 'rtAudience': s.rtAudience,
      if (s.imdb != null) 'imdb': s.imdb,
      if (s.community != null) 'community': s.community,
      if (s.letterboxd != null) 'letterboxd': s.letterboxd,
      if (s.metacritic != null) 'metacritic': s.metacritic,
      if (s.metacriticUser != null) 'metacriticUser': s.metacriticUser,
      if (s.trakt != null) 'trakt': s.trakt,
      if (s.rogerEbert != null) 'rogerEbert': s.rogerEbert,
      if (s.myAnimeList != null) 'myAnimeList': s.myAnimeList,
    };

CachedScores _scoresFromJson(Map<String, dynamic> j) => (
      rtCritic: (j['rtCritic'] as num?)?.toInt(),
      rtAudience: (j['rtAudience'] as num?)?.toInt(),
      imdb: (j['imdb'] as num?)?.toDouble(),
      community: (j['community'] as num?)?.toDouble(),
      letterboxd: (j['letterboxd'] as num?)?.toInt(),
      metacritic: (j['metacritic'] as num?)?.toInt(),
      metacriticUser: (j['metacriticUser'] as num?)?.toInt(),
      trakt: (j['trakt'] as num?)?.toInt(),
      rogerEbert: (j['rogerEbert'] as num?)?.toInt(),
      myAnimeList: (j['myAnimeList'] as num?)?.toInt(),
    );

/// A synchronous snapshot of the images cached for downloads (posters,
/// backdrops, cast photos, episode stills), so image widgets can fall back to a
/// local file when offline without an async disk lookup. Keyed by relative path
/// under the downloads dir, e.g. `backdrops/<id>.jpg`.
class DownloadImageCache {
  final String base;
  final Set<String> names;
  const DownloadImageCache(this.base, this.names);
  File? file(String rel) => names.contains(rel) ? File('$base/$rel') : null;
}

class DownloadImageCacheNotifier extends Notifier<DownloadImageCache?> {
  @override
  DownloadImageCache? build() => null;
  void reset(String base, Set<String> names) =>
      state = DownloadImageCache(base, names);
  void add(String rel) {
    final c = state;
    if (c == null || c.names.contains(rel)) return;
    state = DownloadImageCache(c.base, {...c.names, rel});
  }
}

/// Local images cached for offline downloads, consulted by [MediaImage] and the
/// cast avatars so a downloaded item's art still renders with no network.
final downloadImageCacheProvider =
    NotifierProvider<DownloadImageCacheNotifier, DownloadImageCache?>(
        DownloadImageCacheNotifier.new);

class DownloadEntry {
  final String itemId;
  final String name;
  final String localPath;
  final DownloadStatus status;
  final double progress;

  /// When this download is a series episode, the parent series' id and name plus
  /// its season and episode numbers, so the Downloads screen can group a series'
  /// episodes by season under one collapsible header (and cancel/remove them as
  /// a set). Null for a standalone movie.
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  /// The Jellyfin item type ('Movie', 'Episode', …) so the Downloads library can
  /// split Movies from TV, and a locally-cached poster (a movie's own; a series'
  /// poster for an episode) so covers show offline. [year]/[communityRating]/
  /// [criticRating] carry the library card's year and rating badge — a movie's
  /// own, or the series' for an episode — so a downloaded card matches a browse
  /// card exactly, offline.
  final String? type;
  final String? posterPath;
  /// An episode's own Primary image tag (its landscape still), so the download
  /// detail's episode list can load the thumbnail online and match it to the
  /// cached copy offline. Null for movies.
  final String? imageTag;
  /// Runtime in Jellyfin ticks (100ns), so a downloaded music track shows its
  /// duration offline in the album view. Null when unknown.
  final int? runTimeTicks;
  final int? year;
  final double? communityRating;
  final double? criticRating;

  /// The library card's watched badge: how many episodes are unwatched (a
  /// series' count, captured at download time) and whether the item is fully
  /// played. Static for now; a later pass syncs it with the server.
  final int? unplayedItemCount;
  final bool? played;

  /// Local watched state, toggled from the download detail page. Download-only —
  /// never synced to the server. Null falls back to the server's [played] at
  /// download time.
  final bool? watchedLocal;

  const DownloadEntry({
    required this.itemId,
    required this.name,
    required this.localPath,
    required this.status,
    this.progress = 0,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.type,
    this.posterPath,
    this.imageTag,
    this.runTimeTicks,
    this.year,
    this.communityRating,
    this.criticRating,
    this.unplayedItemCount,
    this.played,
    this.watchedLocal,
  });

  DownloadEntry copyWith(
          {DownloadStatus? status,
          double? progress,
          String? posterPath,
          bool? watchedLocal}) =>
      DownloadEntry(
        itemId: itemId,
        name: name,
        localPath: localPath,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        seriesId: seriesId,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        type: type,
        posterPath: posterPath ?? this.posterPath,
        imageTag: imageTag,
        runTimeTicks: runTimeTicks,
        year: year,
        communityRating: communityRating,
        criticRating: criticRating,
        unplayedItemCount: unplayedItemCount,
        played: played,
        watchedLocal: watchedLocal ?? this.watchedLocal,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'name': name,
        'localPath': localPath,
        if (seriesId != null) 'seriesId': seriesId,
        if (seriesName != null) 'seriesName': seriesName,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        if (type != null) 'type': type,
        if (posterPath != null) 'posterPath': posterPath,
        if (imageTag != null) 'imageTag': imageTag,
        if (runTimeTicks != null) 'runTimeTicks': runTimeTicks,
        if (year != null) 'year': year,
        if (communityRating != null) 'communityRating': communityRating,
        if (criticRating != null) 'criticRating': criticRating,
        if (unplayedItemCount != null) 'unplayedItemCount': unplayedItemCount,
        if (played != null) 'played': played,
        if (watchedLocal != null) 'watchedLocal': watchedLocal,
      };

  factory DownloadEntry.fromJson(Map<String, dynamic> j) => DownloadEntry(
        itemId: j['itemId'] as String,
        name: j['name'] as String? ?? '',
        localPath: j['localPath'] as String,
        status: DownloadStatus.complete,
        progress: 1,
        seriesId: j['seriesId'] as String?,
        seriesName: j['seriesName'] as String?,
        seasonNumber: (j['seasonNumber'] as num?)?.toInt(),
        episodeNumber: (j['episodeNumber'] as num?)?.toInt(),
        type: j['type'] as String?,
        posterPath: j['posterPath'] as String?,
        imageTag: j['imageTag'] as String?,
        runTimeTicks: (j['runTimeTicks'] as num?)?.toInt(),
        year: (j['year'] as num?)?.toInt(),
        communityRating: (j['communityRating'] as num?)?.toDouble(),
        criticRating: (j['criticRating'] as num?)?.toDouble(),
        unplayedItemCount: (j['unplayedItemCount'] as num?)?.toInt(),
        played: j['played'] as bool?,
        watchedLocal: j['watchedLocal'] as bool?,
      );
}

/// Manages offline downloads. Downloads run through [FileDownloader], which on
/// Android hands them to a foreground service + WorkManager so they continue
/// (with a system progress notification) when the app is backgrounded, instead
/// of dying with the Dart isolate the way an in-process HTTP download would.
/// Desktop uses the same API and just downloads normally.
class DownloadsController extends AsyncNotifier<Map<String, DownloadEntry>> {
  static const _key = 'fathom_downloads';
  static const _dir = 'fathom_downloads';
  final _downloader = FileDownloader();
  StreamSubscription<TaskUpdate>? _updatesSub;

  @override
  Future<Map<String, DownloadEntry>> build() async {
    // System download notification (Android shows a progress bar; a no-op where
    // unsupported). Configured once for the app's lifetime.
    _downloader.configureNotification(
      running: TaskNotification(tr.notifDownloading, '{displayName}'),
      complete: TaskNotification(tr.notifDownloadComplete, '{displayName}'),
      error: TaskNotification(tr.notifDownloadFailed, '{displayName}'),
      progressBar: true,
    );
    // Reconnect to any task that finished/advanced while the app was away, then
    // listen for live status/progress updates from the native downloader.
    _updatesSub = _downloader.updates.listen(_onUpdate);
    ref.onDispose(() => _updatesSub?.cancel());
    unawaited(_downloader.resumeFromBackground());
    // Index the cached art on disk so image widgets can fall back offline.
    unawaited(_initImageCache());

    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return {};
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => DownloadEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return {for (final e in list) e.itemId: e};
    } catch (_) {
      return {};
    }
  }

  /// Handle a native status/progress update. Task ids are the item ids.
  void _onUpdate(TaskUpdate update) {
    final id = update.task.taskId;
    if (update is TaskProgressUpdate) {
      final m = _map;
      final e = m[id];
      if (e == null || update.progress < 0) return;
      m[id] = e.copyWith(progress: update.progress.clamp(0.0, 1.0));
      state = AsyncData(m);
    } else if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.complete:
          _markComplete(id, update.task.metaData);
        case TaskStatus.failed:
        case TaskStatus.notFound:
        case TaskStatus.canceled:
          debugPrint('[download] $id ${update.status.name}: '
              'code=${update.responseStatusCode} '
              'exception=${update.exception}');
          final m = _map;
          final e = m[id];
          if (e != null) {
            m[id] = e.copyWith(status: DownloadStatus.failed);
            state = AsyncData(m);
          }
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
        case TaskStatus.paused:
          final m = _map;
          final e = m[id];
          if (e != null && e.status != DownloadStatus.downloading) {
            m[id] = e.copyWith(status: DownloadStatus.downloading);
            state = AsyncData(m);
          }
      }
    }
  }

  Future<void> _markComplete(String id, String name) async {
    final m = _map;
    final e = m[id];
    if (e == null) return;
    m[id] = e.copyWith(status: DownloadStatus.complete, progress: 1);
    state = AsyncData(m);
    await _persistComplete();
    await pushAppNotification(ref,
        kind: AppNotifKind.downloadComplete,
        title: tr.notifDownloadComplete,
        body: name.isEmpty ? e.name : name,
        enabled:
            ref.read(preferencesProvider).asData?.value.notifDownloads ?? true,
        route: '/downloads');
  }

  Map<String, DownloadEntry> get _map =>
      Map.of(state.asData?.value ?? const {});

  Future<void> _persistComplete() async {
    final complete = _map.values
        .where((e) => e.status == DownloadStatus.complete)
        .map((e) => e.toJson())
        .toList();
    await ref
        .read(secureStorageProvider)
        .write(key: _key, value: jsonEncode(complete));
  }

  String? localPathFor(String itemId) {
    final e = state.asData?.value[itemId];
    return e != null && e.status == DownloadStatus.complete ? e.localPath : null;
  }

  /// Downloads [item]. A Movie/Episode/Video/Recording downloads its single
  /// file; a Series or Season expands into episodes, and a MusicAlbum/MusicArtist
  /// expands into its audio tracks (Jellyfin folders have no stream of their
  /// own), skipping anything already downloaded or in flight so a repeat tap
  /// only picks up what's missing. Audio uses the audio stream endpoint.
  Future<void> download(BaseItemDto item, {String? asType}) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _loadRecordingKeys();

    if (item.type == 'Series' || item.type == 'Season') {
      final episodes = await client.getEpisodes(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        seriesId: item.type == 'Season' ? (item.seriesId ?? item.id) : item.id,
        seasonId: item.type == 'Season' ? item.id : null,
      );
      await downloadEpisodes(episodes, asType: asType);
      return;
    }

    // A music album/artist expands into its tracks, grouped under the album so
    // the Downloads library shows one album card (like a series' episodes).
    if (item.type == 'MusicAlbum' || item.type == 'MusicArtist') {
      final res = await client.getItems(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        parentId: item.id,
        includeItemTypes: 'Audio',
        sortBy: 'ParentIndexNumber,IndexNumber',
        recursive: item.type == 'MusicArtist',
        limit: 500,
      );
      // Cache the album's cover + detail once, then enqueue each track.
      unawaited(_cacheDetail(item));
      for (final track in res.items) {
        await _enqueueAudio(track, session,
            groupId: item.id, groupName: item.name);
      }
      return;
    }
    if (item.type == 'Audio') {
      await _enqueueAudio(item, session,
          groupId: item.albumId, groupName: item.album);
      return;
    }

    // Everything else (movie/episode/recording/music video) is a single video.
    await _enqueue(
      item,
      client.videoStreamUrl(
        baseUrl: session.baseUrl,
        itemId: item.id,
        token: session.accessToken,
      ),
      asType: asType,
    );
  }

  /// Enqueues one audio track, grouped under its album so the Downloads library
  /// and the album detail can treat the album like a series of tracks.
  Future<void> _enqueueAudio(BaseItemDto track, Session session,
      {String? groupId, String? groupName}) async {
    if (_map.containsKey(track.id)) return; // already downloaded / in flight
    final client = ref.read(jellyfinClientProvider);
    await _enqueue(
      track,
      client.audioStreamUrl(
        baseUrl: session.baseUrl,
        itemId: track.id,
        token: session.accessToken,
      ),
      groupId: groupId,
      groupName: groupName,
    );
  }

  /// Enqueues each of [episodes] that isn't already downloaded or in flight.
  /// Lets a caller download a chosen scope (a whole series, or one season) that
  /// it has already resolved to a concrete episode list.
  Future<void> downloadEpisodes(List<BaseItemDto> episodes,
      {String? asType}) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _loadRecordingKeys();
    // Fetch the series once for the library card's year + rating — the show
    // card shows the SERIES's, not each episode's.
    int? year;
    double? community;
    double? critic;
    int? unplayed;
    bool? played;
    final seriesId = episodes.isNotEmpty ? episodes.first.seriesId : null;
    if (seriesId != null) {
      try {
        final series = await client.getItem(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: seriesId,
        );
        year = series.productionYear;
        community = series.communityRating;
        critic = series.criticRating;
        unplayed = series.userData.unplayedItemCount;
        played = series.userData.played;
      } catch (_) {}
    }
    for (final ep in episodes) {
      final existing = _map[ep.id];
      if (existing != null &&
          (existing.status == DownloadStatus.complete ||
              existing.status == DownloadStatus.downloading)) {
        continue;
      }
      await _enqueue(
        ep,
        client.videoStreamUrl(
          baseUrl: session.baseUrl,
          itemId: ep.id,
          token: session.accessToken,
        ),
        year: year,
        community: community,
        critic: critic,
        unplayed: unplayed,
        played: played,
        asType: asType,
      );
    }
  }

  /// Enqueues a single playable [item] at [url]. Shared by movie/episode
  /// downloads and by each episode of a series/season download. [year]/
  /// [community]/[critic] override the item's own (episodes pass the series'
  /// values so a show card matches the series' browse card); a movie passes
  /// none and uses its own.
  // Ids and series-ids that appear in the server's DVR recordings list, loaded
  // just before a download so an item can be matched to a recording (the server
  // puts no field on a recorded item — the list is the only source of truth).
  Set<String> _recordingKeys = const {};

  Future<void> _loadRecordingKeys() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) {
      _recordingKeys = const {};
      return;
    }
    try {
      final recs = await ref.read(jellyfinClientProvider).getRecordings(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
          );
      final keys = <String>{};
      for (final r in recs) {
        keys.add(r.id);
        if (r.seriesId != null) keys.add(r.seriesId!);
      }
      _recordingKeys = keys;
    } catch (_) {
      _recordingKeys = const {};
    }
  }

  /// Whether a download should be filed under Recordings: it arrived via the
  /// recordings context (asType), carries a source ChannelId only a DVR
  /// recording keeps, or its id/series matches the server's recordings list.
  bool _recordingKind(BaseItemDto item, String? asType) =>
      asType == 'Recording' ||
      (item.channelId != null && item.type != 'TvChannel') ||
      _recordingKeys.contains(item.id) ||
      (item.seriesId != null && _recordingKeys.contains(item.seriesId));

  /// The on-disk subfolder a download's media file lands in, mirroring the
  /// Movies/TV Shows/Music/Recordings sections of the Downloads screen so a
  /// user pointed at a custom [Prefs.jellyfinDownloadPath] sees the same
  /// organization in a file manager.
  String _typeFolder(String? type) => switch (type) {
        'Recording' => 'Recordings',
        'Audio' || 'MusicAlbum' || 'MusicVideo' => 'Music',
        'Series' || 'Episode' => 'TV Shows',
        _ => 'Movies',
      };

  /// Where a download task should write, honoring a custom
  /// [Prefs.jellyfinDownloadPath] if set, else the app-private default.
  ({BaseDirectory base, String dir}) _taskLocation(String folder) {
    final custom =
        ref.read(preferencesProvider).asData?.value.jellyfinDownloadPath ?? '';
    if (custom.isNotEmpty) {
      return (base: BaseDirectory.root, dir: '$custom/$folder');
    }
    return (base: BaseDirectory.applicationSupport, dir: '$_dir/$folder');
  }

  /// The root directory for cached art/ratings/metadata (not split by media
  /// type — those already have their own posters/backdrops/ratings/meta
  /// subfolders). Honors a custom [Prefs.jellyfinDownloadPath] if set.
  Future<String> _rootPath() async {
    final custom =
        ref.read(preferencesProvider).asData?.value.jellyfinDownloadPath ?? '';
    if (custom.isNotEmpty) return custom;
    final base = await getApplicationSupportDirectory();
    return '${base.path}/$_dir';
  }

  Future<void> _enqueue(BaseItemDto item, String url,
      {int? year,
      double? community,
      double? critic,
      int? unplayed,
      bool? played,
      String? groupId,
      String? groupName,
      String? asType}) async {
    // A DVR recording either came in via the recordings context (asType) or
    // carries a source ChannelId a normal library item never has. Either way
    // it's stored as 'Recording' so it lands in the Recordings section.
    final type = _recordingKind(item, asType) ? 'Recording' : (asType ?? item.type);
    final loc = _taskLocation(_typeFolder(type));
    // taskId = item id so updates map straight back; displayName drives the
    // system notification text; metaData carries the name across an app restart.
    final task = DownloadTask(
      taskId: item.id,
      url: url,
      filename: item.id,
      directory: loc.dir,
      baseDirectory: loc.base,
      updates: Updates.statusAndProgress,
      retries: 2,
      allowPause: true,
      displayName: item.name,
      metaData: item.name,
    );
    final path = await task.filePath();

    final map = _map;
    map[item.id] = DownloadEntry(
      itemId: item.id,
      name: item.name,
      localPath: path,
      status: DownloadStatus.downloading,
      // groupId/groupName let an album stand in as the grouping parent for its
      // tracks (the same slot a series uses for its episodes).
      seriesId: groupId ?? item.seriesId,
      seriesName: groupName ?? item.seriesName,
      seasonNumber: item.parentIndexNumber,
      episodeNumber: item.indexNumber,
      type: type,
      imageTag: item.isEpisode ? item.primaryImageTag : null,
      runTimeTicks: item.runTimeTicks,
      year: year ?? item.productionYear,
      communityRating: community ?? item.communityRating,
      criticRating: critic ?? item.criticRating,
      unplayedItemCount: unplayed ?? item.userData.unplayedItemCount,
      played: played ?? item.userData.played,
    );
    state = AsyncData(map);

    // Cache the cover alongside the media so the Downloads library shows it
    // offline. Best-effort and in the background, so it never delays the queue.
    unawaited(_cachePoster(item).then((p) {
      if (p == null) return;
      final m = _map;
      final e = m[item.id];
      if (e != null) {
        m[item.id] = e.copyWith(posterPath: p);
        state = AsyncData(m);
        unawaited(_persistComplete());
      }
    }));
    // An episode's own Primary is its landscape still; cache it so the download
    // detail's episode list shows thumbnails offline.
    if (item.isEpisode && item.primaryImageTag != null) {
      unawaited(_saveImage(
          sub: 'episodes',
          name: item.id,
          itemId: item.id,
          type: 'Primary',
          tag: item.primaryImageTag,
          maxWidth: 640));
    }
    // Cache the full detail (overview, cast, genres, ratings) so the download
    // detail page has the familiar server-style info offline.
    unawaited(_cacheDetail(item));

    debugPrint('[download] enqueue ${item.id} "${item.name}" -> $path');
    final ok = await _downloader.enqueue(task);
    debugPrint('[download] enqueue ${item.id} accepted=$ok');
    if (!ok) {
      final failed = _map;
      final e = failed[item.id];
      if (e != null) {
        failed[item.id] = e.copyWith(status: DownloadStatus.failed);
        state = AsyncData(failed);
      }
    }
  }

  /// Cancels every in-progress download at once (leaving completed ones in
  /// place). Backs the Downloads screen's "Cancel All".
  Future<void> cancelActive() async {
    final active = [
      for (final e in _map.values)
        if (e.status == DownloadStatus.downloading) e.itemId,
    ];
    for (final id in active) {
      await delete(id);
    }
  }

  /// Downloads the item's cover to a local file so the Downloads library can
  /// show it offline. A movie caches its own poster; an episode caches its
  /// series' poster (shared across the series' episodes, so it's fetched once).
  /// Returns the local path, or null on any failure. Best-effort.
  Future<String?> _cachePoster(BaseItemDto item) async {
    final String key;
    final String? tag;
    if (item.isEpisode && item.seriesId != null) {
      // An episode caches the series' poster (shared across its episodes).
      key = item.seriesId!;
      tag = item.seriesPrimaryImageTag;
    } else if (item.type == 'Audio' && item.albumId != null) {
      // A track caches its album cover (shared across the album's tracks).
      key = item.albumId!;
      tag = item.albumPrimaryImageTag;
    } else {
      key = item.id;
      tag = item.primaryImageTag;
    }
    return _saveImage(
        sub: 'posters', name: key, itemId: key, type: 'Primary', tag: tag,
        maxWidth: 400);
  }

  /// Scans the on-disk art folders once at startup and publishes a synchronous
  /// index so [MediaImage] and the cast avatars can fall back to a local file
  /// offline. Cheap: a few directory listings, done off the critical path.
  Future<void> _initImageCache() async {
    try {
      final root = await _rootPath();
      final names = <String>{};
      for (final sub in const ['posters', 'backdrops', 'people', 'episodes']) {
        final d = Directory('$root/$sub');
        if (!d.existsSync()) continue;
        for (final f in d.listSync()) {
          if (f is File) names.add('$sub/${f.uri.pathSegments.last}');
        }
      }
      ref.read(downloadImageCacheProvider.notifier).reset(root, names);
    } catch (_) {}
  }

  /// Downloads one image to `<downloads>/<sub>/<name>.jpg` and records it in the
  /// offline image index. Returns the local path, or null on any failure.
  /// Best-effort and idempotent (an existing file is kept).
  Future<String?> _saveImage({
    required String sub,
    required String name,
    required String itemId,
    required String type,
    String? tag,
    int? maxWidth,
    int? maxHeight,
  }) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return null;
    final client = ref.read(jellyfinClientProvider);
    final rel = '$sub/$name.jpg';
    try {
      final root = await _rootPath();
      final dir = Directory('$root/$sub');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$name.jpg');
      if (file.existsSync() && file.lengthSync() > 0) {
        ref.read(downloadImageCacheProvider.notifier).add(rel);
        return file.path;
      }
      final url = client.imageUrl(
        baseUrl: session.baseUrl,
        itemId: itemId,
        type: type,
        tag: tag,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      final dio = await secureDio();
      final resp = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: ref.read(imageHeadersProvider),
        ),
      );
      final data = resp.data;
      if (data != null && data.isNotEmpty) {
        file.writeAsBytesSync(data);
        ref.read(downloadImageCacheProvider.notifier).add(rel);
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Caches the hero backdrop and cast photos for a movie/series so the download
  /// detail page renders the familiar art offline. Best-effort, in the
  /// background. Ratings/overview travel in the cached detail JSON already.
  Future<void> _cacheImages(BaseItemDto detail) async {
    if (detail.backdropImageTags.isNotEmpty) {
      await _saveImage(
        sub: 'backdrops',
        name: detail.id,
        itemId: detail.id,
        type: 'Backdrop',
        tag: detail.backdropImageTags.first,
        maxWidth: 1280,
      );
    }
    final cast = detail.people.where((p) =>
        p.primaryImageTag != null &&
        p.id.isNotEmpty &&
        (p.type == null || p.type == 'Actor' || p.type == 'GuestStar'));
    for (final p in cast.take(24)) {
      await _saveImage(
        sub: 'people',
        name: p.id,
        itemId: p.id,
        type: 'Primary',
        tag: p.primaryImageTag,
        maxHeight: 200,
      );
    }
  }

  /// Fetches and caches the extra online ratings (RT/Letterboxd/Metacritic/…)
  /// for a movie/series to `<downloads>/ratings/<id>.json`, so they show on the
  /// download detail page offline. Best-effort; skips writing when the fetch
  /// returns nothing (offline or no keys) so an existing cache is never clobbered.
  Future<void> _writeRatings(BaseItemDto detail) async {
    final tmdb = int.tryParse(detail.tmdbId ?? '');
    final type = detail.seerrMediaType;
    if (tmdb == null || type == null) return;
    try {
      final ext = await ref
          .read(jellyfinItemRatingsProvider((mediaType: type, tmdbId: tmdb))
              .future);
      final mdb = await ref
          .read(mdbListRatingsProvider((mediaType: type, tmdbId: tmdb)).future);
      if (ext == null && mdb == null) return; // nothing extra to cache
      final scores = mergeCachedScores(
        community: detail.communityRating,
        critic: detail.criticRating?.round(),
        ext: ext,
        mdb: mdb,
      );
      final root = await _rootPath();
      final dir = Directory('$root/ratings');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('${dir.path}/${detail.id}.json')
          .writeAsStringSync(jsonEncode(_scoresToJson(scores)));
    } catch (_) {}
  }

  /// Refreshes the cached ratings for an open download detail page when online,
  /// keeping the offline copy current. No-op offline (see [_writeRatings]).
  Future<void> refreshRatings(BaseItemDto detail) async {
    await _writeRatings(detail);
    ref.invalidate(downloadRatingsProvider(detail.id));
  }

  /// Loads the cached extra ratings for a downloaded movie/series, or null.
  Future<CachedScores?> loadRatings(String key) async {
    try {
      final root = await _rootPath();
      final file = File('$root/ratings/$key.json');
      if (!file.existsSync()) return null;
      return _scoresFromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Caches an item's full detail JSON (the series' for an episode) under
  /// `<downloads>/meta/<key>.json`, so the download detail page can render the
  /// familiar overview/cast/ratings offline. Fetched once per movie/series.
  Future<void> _cacheDetail(BaseItemDto item) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    final key =
        (item.isEpisode && item.seriesId != null) ? item.seriesId! : item.id;
    try {
      final root = await _rootPath();
      final dir = Directory('$root/meta');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$key.json');
      if (file.existsSync() && file.lengthSync() > 0) return;
      final json = await client.getItemJson(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: key,
      );
      if (json != null) {
        file.writeAsStringSync(jsonEncode(json));
        // Backdrop + cast photos + extra ratings for offline detail rendering.
        try {
          final detail = BaseItemDto.fromJson(json);
          await _cacheImages(detail);
          await _writeRatings(detail);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Loads a downloaded item's cached full detail (movie or series), for the
  /// download detail page. Null if it wasn't cached.
  Future<BaseItemDto?> loadDetail(String key) async {
    try {
      final root = await _rootPath();
      final file = File('$root/meta/$key.json');
      if (!file.existsSync()) return null;
      return BaseItemDto.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Cancels/removes every download belonging to one series at once, backing the
  /// series group's cancel/remove action on the Downloads screen.
  Future<void> deleteSeries(String seriesId) async {
    final ids = [
      for (final e in _map.values)
        if (e.seriesId == seriesId) e.itemId,
    ];
    for (final id in ids) {
      await delete(id);
    }
  }

  /// Local watched state for a downloaded item: the download detail page toggles
  /// it, but it's never sent to the server. Falls back to the server's played
  /// state captured at download time.
  bool isWatched(DownloadEntry e) => e.watchedLocal ?? e.played ?? false;

  Future<void> setWatched(String itemId, bool watched) async {
    final m = _map;
    final e = m[itemId];
    if (e == null) return;
    m[itemId] = e.copyWith(watchedLocal: watched);
    state = AsyncData(m);
    await _persistComplete();
  }

  /// Cancels/removes one season of a series, for the per-season action shown
  /// when a download spans multiple seasons.
  Future<void> deleteSeason(String seriesId, int? seasonNumber) async {
    final ids = [
      for (final e in _map.values)
        if (e.seriesId == seriesId && e.seasonNumber == seasonNumber) e.itemId,
    ];
    for (final id in ids) {
      await delete(id);
    }
  }

  Future<void> delete(String itemId) async {
    // Cancel first, in case it's still running natively.
    await _downloader.cancelTaskWithId(itemId);
    final map = _map;
    final e = map.remove(itemId);
    if (e != null) {
      final f = File(e.localPath);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    state = AsyncData(map);
    await _persistComplete();
  }
}

final downloadsProvider =
    AsyncNotifierProvider<DownloadsController, Map<String, DownloadEntry>>(
        DownloadsController.new);

/// The cached extra ratings for a downloaded movie/series, for the download
/// detail page's score pills offline. Keyed by the item/series id.
final downloadRatingsProvider =
    FutureProvider.autoDispose.family<CachedScores?, String>((ref, key) async {
  return ref.read(downloadsProvider.notifier).loadRatings(key);
});

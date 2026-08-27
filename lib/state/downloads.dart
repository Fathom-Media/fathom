import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart' show Options, ResponseType;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../models/base_item.dart';
import '../services/secure_http.dart';
import 'library_providers.dart';
import 'notifications_controller.dart';
import 'preferences.dart';
import 'providers.dart';
import 'session_controller.dart';

enum DownloadStatus { downloading, complete, failed }

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
  /// poster for an episode) so covers show offline.
  final String? type;
  final String? posterPath;

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
  });

  DownloadEntry copyWith(
          {DownloadStatus? status, double? progress, String? posterPath}) =>
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

  /// Downloads [item]. A Movie/Episode/Video downloads its single file; a Series
  /// or Season expands into its episodes and enqueues each one (Jellyfin folders
  /// have no stream of their own), skipping any episode already downloaded or in
  /// flight so a repeat tap only picks up what's missing.
  Future<void> download(BaseItemDto item) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);

    if (item.type == 'Series' || item.type == 'Season') {
      final episodes = await client.getEpisodes(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        seriesId: item.type == 'Season' ? (item.seriesId ?? item.id) : item.id,
        seasonId: item.type == 'Season' ? item.id : null,
      );
      await downloadEpisodes(episodes);
      return;
    }

    await _enqueue(
      item,
      client.videoStreamUrl(
        baseUrl: session.baseUrl,
        itemId: item.id,
        token: session.accessToken,
      ),
    );
  }

  /// Enqueues each of [episodes] that isn't already downloaded or in flight.
  /// Lets a caller download a chosen scope (a whole series, or one season) that
  /// it has already resolved to a concrete episode list.
  Future<void> downloadEpisodes(List<BaseItemDto> episodes) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
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
      );
    }
  }

  /// Enqueues a single playable [item] at [url]. Shared by movie/episode
  /// downloads and by each episode of a series/season download.
  Future<void> _enqueue(BaseItemDto item, String url) async {
    // taskId = item id so updates map straight back; displayName drives the
    // system notification text; metaData carries the name across an app restart.
    final task = DownloadTask(
      taskId: item.id,
      url: url,
      filename: item.id,
      directory: _dir,
      baseDirectory: BaseDirectory.applicationSupport,
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
      seriesId: item.seriesId,
      seriesName: item.seriesName,
      seasonNumber: item.parentIndexNumber,
      episodeNumber: item.indexNumber,
      type: item.type,
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
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return null;
    final client = ref.read(jellyfinClientProvider);
    final String key;
    final String? tag;
    if (item.isEpisode && item.seriesId != null) {
      key = item.seriesId!;
      tag = item.seriesPrimaryImageTag;
    } else {
      key = item.id;
      tag = item.primaryImageTag;
    }
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/$_dir/posters');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$key.jpg');
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
      final url = client.imageUrl(
        baseUrl: session.baseUrl,
        itemId: key,
        type: 'Primary',
        tag: tag,
        maxWidth: 400,
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
        return file.path;
      }
    } catch (_) {}
    return null;
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

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../models/base_item.dart';
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

  const DownloadEntry({
    required this.itemId,
    required this.name,
    required this.localPath,
    required this.status,
    this.progress = 0,
  });

  DownloadEntry copyWith({DownloadStatus? status, double? progress}) =>
      DownloadEntry(
        itemId: itemId,
        name: name,
        localPath: localPath,
        status: status ?? this.status,
        progress: progress ?? this.progress,
      );

  Map<String, dynamic> toJson() =>
      {'itemId': itemId, 'name': name, 'localPath': localPath};

  factory DownloadEntry.fromJson(Map<String, dynamic> j) => DownloadEntry(
        itemId: j['itemId'] as String,
        name: j['name'] as String? ?? '',
        localPath: j['localPath'] as String,
        status: DownloadStatus.complete,
        progress: 1,
      );
}

/// Manages offline downloads: downloading video files to local storage,
/// tracking progress, and persisting the completed set.
class DownloadsController extends AsyncNotifier<Map<String, DownloadEntry>> {
  static const _key = 'fathom_downloads';
  final _dio = Dio();

  @override
  Future<Map<String, DownloadEntry>> build() async {
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

  Future<void> download(BaseItemDto item) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    final url = client.videoStreamUrl(
      baseUrl: session.baseUrl,
      itemId: item.id,
      token: session.accessToken,
    );

    final dir = Directory('${(await getApplicationSupportDirectory()).path}'
        '/fathom_downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = '${dir.path}/${item.id}';

    final map = _map;
    map[item.id] = DownloadEntry(
      itemId: item.id,
      name: item.name,
      localPath: path,
      status: DownloadStatus.downloading,
    );
    state = AsyncData(map);

    try {
      await _dio.download(url, path, onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final m = _map;
        final e = m[item.id];
        if (e == null) return;
        m[item.id] = e.copyWith(progress: received / total);
        state = AsyncData(m);
      });
      final done = _map;
      done[item.id] = done[item.id]!
          .copyWith(status: DownloadStatus.complete, progress: 1);
      state = AsyncData(done);
      await _persistComplete();
      await pushAppNotification(ref,
          kind: AppNotifKind.downloadComplete,
          title: tr.notifDownloadComplete,
          body: item.name,
          enabled:
              ref.read(preferencesProvider).asData?.value.notifDownloads ?? true,
          route: '/downloads');
    } catch (_) {
      final failed = _map;
      failed[item.id] =
          failed[item.id]!.copyWith(status: DownloadStatus.failed);
      state = AsyncData(failed);
    }
  }

  Future<void> delete(String itemId) async {
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

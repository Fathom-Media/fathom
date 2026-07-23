import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/youtube_video.dart';
import 'package:fathom/services/youtube_download.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/youtube_providers.dart';

class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    // Storage is slow in reality (a keyring round-trip). The delay is the
    // point: it makes build() finish after start() has already set state.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return store[key];
  }
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value != null) store[key] = value;
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Never finishes, so the download stays "in progress" like a real one.
class _HangingDownloader extends YoutubeDownloader {
  @override
  Future<File> download({
    required String videoUrl,
    required String title,
    required Directory into,
    YtDownloadKind kind = YtDownloadKind.video,
    int? preferredHeight,
    YtAudioFormat audioFormat = YtAudioFormat.m4a,
    int audioBitrate = 320,
    YtVideoContainer container = YtVideoContainer.mp4,
    int retries = 3,
    required void Function(YtDownloadProgress) onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress(
        const YtDownloadProgress(received: 1000, total: 10000, stage: 'video'));
    await Future<void>.delayed(const Duration(seconds: 30));
    return File('${into.path}/x.mp4');
  }
}

void main() {
  test('a started download appears in the list straight away', () async {
    final dir = Directory.systemTemp.createTempSync('fathom_dlstate');
    addTearDown(() => dir.deleteSync(recursive: true));

    final c = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(_FakeStorage()),
      youtubeDownloaderProvider.overrideWithValue(_HangingDownloader()),
      youtubeDownloadDirProvider(YtDownloadKind.video)
          .overrideWith((ref) async => dir),
    ]);
    addTearDown(c.dispose);

    final video = YoutubeVideo(
      id: 'v1',
      title: 'A video',
      author: 'Someone',
      url: 'https://www.youtube.com/watch?v=v1',
      thumbnailUrl: 't',
    );

    // Exactly what the sheet does: reads the notifier and calls start, without
    // the Downloads tab ever having been opened, so build() has not run yet.
    unawaited(c.read(youtubeDownloadsProvider.notifier).start(video));

    // Let build() finish and any progress land.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final list = c.read(youtubeDownloadsProvider).asData?.value ?? const [];
    // ignore: avoid_print
    print('DOWNLOADS after start -> ${list.length} ${list.map((d) => d.status)}');
    expect(list, hasLength(1),
        reason: 'the download vanished: build() resolved after start() set '
            'state and overwrote it');
    expect(list.single.id, 'v1');
    expect(list.single.isActive, isTrue);
  });
}

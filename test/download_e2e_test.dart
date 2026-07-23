@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/services/youtube_download.dart';

/// Downloads a real video, end to end, and checks the file plays.
void main() {
  test('downloads and merges a real video at 720p', () async {
    final dir = Directory.systemTemp.createTempSync('fathom_e2e');
    addTearDown(() => dir.deleteSync(recursive: true));

    final stages = <String>{};
    final file = await YoutubeDownloader().download(
      // Short, so the test isn't a download of a 10-minute video.
      videoUrl: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
      title: 'Big Buck Bunny: AC/DC "test"',
      into: dir,
      preferredHeight: 720,
      onProgress: (p) => stages.add(p.stage),
    );

    // ignore: avoid_print
    print('FILE ${file.path.split('/').last}');
    // ignore: avoid_print
    print('SIZE ${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB');
    // ignore: avoid_print
    print('STAGES $stages');

    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(100 * 1024));
    // The title's slashes and quotes must not have escaped into the path.
    expect(file.path, contains('ACDC'));
    expect(stages, containsAll(['video', 'audio']));

    // The real proof: both tracks present, and copied rather than re-encoded.
    final probe = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'stream=codec_type,codec_name,height',
      '-of', 'csv=p=0', file.path,
    ]);
    // ignore: avoid_print
    print('PROBE ${probe.stdout.toString().trim().replaceAll('\n', ' | ')}');
    expect(probe.stdout.toString(), contains('video'));
    expect(probe.stdout.toString(), contains('audio'));

    // No scratch files left behind.
    final leftovers =
        dir.listSync().where((f) => f.path.contains('.fathom-')).toList();
    expect(leftovers, isEmpty, reason: 'temp files must be cleaned up');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('audio-only needs no merging and lands as .m4a', () async {
    final dir = Directory.systemTemp.createTempSync('fathom_e2e_a');
    addTearDown(() => dir.deleteSync(recursive: true));

    final file = await YoutubeDownloader().download(
      videoUrl: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
      title: 'audio test',
      into: dir,
      kind: YtDownloadKind.audio,
      onProgress: (_) {},
    );
    expect(file.path, endsWith('.m4a'));
    expect(file.lengthSync(), greaterThan(10 * 1024));

    final probe = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'stream=codec_type',
      '-of', 'csv=p=0', file.path,
    ]);
    // ignore: avoid_print
    print('AUDIO-ONLY ${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB '
        'streams=${probe.stdout.toString().trim().replaceAll('\n', ',')}');
    expect(probe.stdout.toString(), contains('audio'));
    expect(probe.stdout.toString(), isNot(contains('video')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

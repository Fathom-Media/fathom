import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/services/youtube_download.dart';

void main() {
  group('file names', () {
    test('strips characters a filesystem would choke on', () {
      // A slash is the dangerous one: it silently writes into a directory that
      // doesn't exist rather than failing loudly.
      expect(
        YoutubeDownloader.safeFileName('AC/DC: Back "In" Black?',
            extension: 'mp4'),
        'ACDC Back In Black.mp4',
      );
      expect(
        YoutubeDownloader.safeFileName(r'a\b*c|d<e>f%g', extension: 'm4a'),
        'abcdefg.m4a',
      );
    });

    test('keeps unicode, which is most of YouTube', () {
      expect(YoutubeDownloader.safeFileName('日本語のタイトル 🎵',
          extension: 'mp4'), '日本語のタイトル 🎵.mp4');
    });

    test('collapses whitespace and trims', () {
      expect(YoutubeDownloader.safeFileName('  a   b  ', extension: 'mp4'),
          'a b.mp4');
    });

    test('an empty or symbol-only title still yields a name', () {
      expect(YoutubeDownloader.safeFileName('', extension: 'mp4'), 'video.mp4');
      expect(YoutubeDownloader.safeFileName('///', extension: 'mp4'),
          'video.mp4');
    });

    test('long titles are cut to fit a filesystem component', () {
      final name =
          YoutubeDownloader.safeFileName('x' * 400, extension: 'mp4');
      expect(name.length, lessThanOrEqualTo(190));
      expect(name, endsWith('.mp4'));
    });
  });

  group('unique paths', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fathom_dl'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('downloading the same video twice does not destroy the first', () {
      final first = YoutubeDownloader.uniqueFile(dir, 'Song.mp4');
      first.writeAsStringSync('one');
      final second = YoutubeDownloader.uniqueFile(dir, 'Song.mp4');
      expect(second.path, endsWith('Song (2).mp4'));
      second.writeAsStringSync('two');
      final third = YoutubeDownloader.uniqueFile(dir, 'Song.mp4');
      expect(third.path, endsWith('Song (3).mp4'));
      // The original is untouched.
      expect(first.readAsStringSync(), 'one');
    });

    test('the suffix goes before the extension, not after', () {
      YoutubeDownloader.uniqueFile(dir, 'a.mp4').writeAsStringSync('x');
      expect(YoutubeDownloader.uniqueFile(dir, 'a.mp4').path,
          endsWith('a (2).mp4'));
    });
  });

  group('progress', () {
    test('fraction is null when the total is unknown', () {
      // Servers don't always send a length; a bare 0% would be a lie.
      const p = YtDownloadProgress(received: 100, total: -1, stage: 'video');
      expect(p.fraction, isNull);
    });

    test('fraction clamps rather than exceeding 1', () {
      const p = YtDownloadProgress(received: 120, total: 100, stage: 'video');
      expect(p.fraction, 1.0);
    });
  });
}

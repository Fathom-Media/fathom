import 'dart:io';

import 'package:fathom/services/youtube_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('comparableFolder', () {
    test('trailing slashes and separators do not make folders differ', () {
      expect(YoutubeDownloader.comparableFolder('/home/me/Videos/'),
          YoutubeDownloader.comparableFolder('/home/me/Videos'));
      expect(
        YoutubeDownloader.comparableFolder(r'C:\Users\Me\Downloads\Fathom',
            windows: true),
        YoutubeDownloader.comparableFolder('c:/users/me/downloads/Fathom/',
            windows: true),
      );
    });

    test('case matters everywhere but Windows', () {
      expect(
        YoutubeDownloader.comparableFolder('/Videos', windows: false) ==
            YoutubeDownloader.comparableFolder('/videos', windows: false),
        isFalse,
      );
    });
  });

  group('moveInto', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('fathom-move-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('moves the file into a folder it creates', () async {
      final file = File('${root.path}/old/clip.mp4')
        ..createSync(recursive: true)
        ..writeAsStringSync('video');
      final moved = await YoutubeDownloader.moveInto(
          file, Directory('${root.path}/new/folder'));
      expect(moved, '${root.path}/new/folder/clip.mp4');
      expect(File(moved).readAsStringSync(), 'video');
      expect(file.existsSync(), isFalse);
    });

    test('never overwrites a file already there', () async {
      final into = Directory('${root.path}/new')..createSync();
      File('${into.path}/clip.mp4').writeAsStringSync('first');
      final file = File('${root.path}/clip.mp4')..writeAsStringSync('second');
      final moved = await YoutubeDownloader.moveInto(file, into);
      expect(moved, '${into.path}/clip (2).mp4');
      expect(File('${into.path}/clip.mp4').readAsStringSync(), 'first');
      expect(File(moved).readAsStringSync(), 'second');
    });
  });
}

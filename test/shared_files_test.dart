import 'package:fathom/services/shared_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('relativeDir', () {
    test('a folder in shared storage becomes a MediaStore relative path', () {
      expect(SharedFiles.relativeDir('/storage/emulated/0/Download/Videos'),
          'Download/Videos');
      expect(SharedFiles.relativeDir('/storage/emulated/0/Movies/'), 'Movies');
    });

    test('anything outside shared storage has no relative path', () {
      // An SD card, and the storage root itself: MediaStore can't write either.
      expect(SharedFiles.relativeDir('/storage/1A2B-3C4D/Movies'), isNull);
      expect(SharedFiles.relativeDir('/storage/emulated/0/'), isNull);
      expect(SharedFiles.relativeDir('/home/me/Videos'), isNull);
    });
  });

  test('default folders put video and audio where their apps look', () {
    expect(SharedFiles.defaultDir(audio: false), 'Movies/Fathom');
    expect(SharedFiles.defaultDir(audio: true), 'Music/Fathom');
  });

  test('mime types follow the extension, whatever its case', () {
    expect(SharedFiles.mimeFor('/a/b/Video.MP4'), 'video/mp4');
    expect(SharedFiles.mimeFor('x.mkv'), 'video/x-matroska');
    expect(SharedFiles.mimeFor('song.m4a'), 'audio/mp4');
    expect(SharedFiles.mimeFor('song.mp3'), 'audio/mpeg');
    expect(SharedFiles.mimeFor('mystery.bin'), 'application/octet-stream');
  });
}

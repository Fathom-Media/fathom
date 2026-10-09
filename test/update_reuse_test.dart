import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fathom/services/app_installer.dart';
import 'package:fathom/services/app_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('an update that is already downloaded', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fathom-update-'));
    tearDown(() => dir.deleteSync(recursive: true));

    ReleaseAsset assetFor(List<int> bytes, {bool withDigest = true}) =>
        ReleaseAsset(
          name: 'Fathom-0.13.1.apk',
          url: 'https://example.invalid/Fathom-0.13.1.apk',
          size: bytes.length,
          sha256: withDigest ? sha256.convert(bytes).toString() : null,
        );

    test('is reused when it matches exactly', () async {
      final bytes = utf8.encode('a complete, signed apk');
      final file = File('${dir.path}/fathom-0.13.1.apk')..writeAsBytesSync(bytes);
      expect(await fileMatchesAsset(file, assetFor(bytes)), isTrue);
    });

    test('is fetched again when it was cut short', () async {
      final bytes = utf8.encode('a complete, signed apk');
      final file = File('${dir.path}/fathom-0.13.1.apk')
        ..writeAsBytesSync(bytes.sublist(0, 10));
      expect(await fileMatchesAsset(file, assetFor(bytes)), isFalse);
    });

    test('is fetched again when it is the right size but damaged', () async {
      final bytes = utf8.encode('a complete, signed apk');
      final damaged = [...bytes]..[3] ^= 0xFF;
      final file = File('${dir.path}/fathom-0.13.1.apk')..writeAsBytesSync(damaged);
      expect(await fileMatchesAsset(file, assetFor(bytes)), isFalse);
    });

    test('without a published checksum, falls back to the size', () async {
      final bytes = utf8.encode('a complete, signed apk');
      final file = File('${dir.path}/fathom-0.13.1.apk')..writeAsBytesSync(bytes);
      expect(await fileMatchesAsset(file, assetFor(bytes, withDigest: false)),
          isTrue);
    });

    test('is not there at all', () async {
      expect(
          await fileMatchesAsset(
              File('${dir.path}/missing.apk'), assetFor(const [1, 2, 3])),
          isFalse);
    });
  });

  group('cleanup at launch', () {
    final now = DateTime(2026, 9, 28);
    bool spent(String name, {String current = '0.13.1-dev02', int ageDays = 0}) =>
        stagedApkIsSpent(name,
            currentVersion: current,
            modified: now.subtract(Duration(days: ageDays)),
            now: now);

    test('keeps a newer download that was never installed', () {
      expect(spent('fathom-0.13.1-dev03.apk'), isFalse);
      expect(spent('fathom-0.13.1.apk'), isFalse);
    });

    test('drops what is already installed, or older', () {
      expect(spent('fathom-0.13.1-dev02.apk'), isTrue);
      expect(spent('fathom-0.13.0.apk'), isTrue);
    });

    test('drops an abandoned download after a week', () {
      expect(spent('fathom-0.13.1.apk', ageDays: 8), isTrue);
      expect(spent('fathom-0.13.1.apk', ageDays: 6), isFalse);
    });

    test('drops the old fixed-name file, and leaves anything else alone', () {
      expect(spent('fathom_update.apk'), isTrue);
      expect(spent('Download'), isFalse);
      expect(spent('some-video.mp4'), isFalse);
    });
  });

  test('reads the checksum GitHub publishes for a release file', () {
    final asset = ReleaseAsset.fromJson({
      'name': 'Fathom-0.13.1.apk',
      'browser_download_url': 'https://example.invalid/a.apk',
      'size': 10,
      'digest': 'sha256:ABCDEF0123',
    });
    expect(asset.sha256, 'abcdef0123');
    expect(ReleaseAsset.fromJson({'name': 'x', 'size': 1}).sha256, isNull);
  });
}

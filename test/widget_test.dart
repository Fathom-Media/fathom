import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/api/jellyfin_client.dart';

void main() {
  group('JellyfinClient.normalizeBaseUrl', () {
    test('adds https when no scheme is given', () {
      expect(JellyfinClient.normalizeBaseUrl('jellyfin.example.com'),
          'https://jellyfin.example.com');
    });

    test('preserves an explicit http scheme and port', () {
      expect(JellyfinClient.normalizeBaseUrl('http://10.0.1.5:8096'),
          'http://10.0.1.5:8096');
    });

    test('strips trailing slashes', () {
      expect(JellyfinClient.normalizeBaseUrl('https://jf.example.com/'),
          'https://jf.example.com');
    });

    test('throws on empty input', () {
      expect(() => JellyfinClient.normalizeBaseUrl('  '),
          throwsA(isA<JellyfinException>()));
    });
  });
}

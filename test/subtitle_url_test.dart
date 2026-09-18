import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/api/jellyfin_client.dart';

// The address below is the one a real 12.0 server served the downloaded
// Bullet Train subtitle from (2026-09-15, 113 KB of SRT). Fetching an item
// plainly returns its external subtitles with no DeliveryUrl at all, so this
// is built rather than read, and a wrong shape means a downloaded subtitle
// silently never loads.
void main() {
  final client = JellyfinClient(deviceId: 'test-device');
  const item = '0a07cbf0ed420efabbcb94c583493b04';

  test('builds the address when the server gives none', () {
    expect(
      client.subtitleUrl(
        baseUrl: 'http://10.0.1.3:8096',
        token: 'TOKEN',
        itemId: item,
        index: 0,
        mediaSourceId: item,
        codec: 'subrip',
      ),
      'http://10.0.1.3:8096/Videos/$item/$item/Subtitles/0/0/Stream.srt'
      '?api_key=TOKEN',
    );
  });

  test('falls back to the item itself as the media source', () {
    expect(
      client.subtitleUrl(
          baseUrl: 'http://s:8096',
          token: 'T',
          itemId: 'abc',
          index: 3,
          codec: 'ass'),
      'http://s:8096/Videos/abc/abc/Subtitles/3/0/Stream.ass?api_key=T',
    );
  });

  test('uses the address the server gave when there is one', () {
    expect(
      client.subtitleUrl(
        baseUrl: 'http://s:8096',
        token: 'T',
        itemId: 'abc',
        index: 2,
        deliveryUrl: '/Videos/abc/abc/Subtitles/2/0/Stream.vtt',
      ),
      'http://s:8096/Videos/abc/abc/Subtitles/2/0/Stream.vtt?api_key=T',
    );
  });

  test('never doubles up the key', () {
    expect(
      client.subtitleUrl(
        baseUrl: 'http://s:8096',
        token: 'T',
        itemId: 'abc',
        index: 2,
        deliveryUrl: 'http://s:8096/x/Stream.srt?api_key=OTHER',
      ),
      'http://s:8096/x/Stream.srt?api_key=OTHER',
    );
  });

  test('asks for each format in its own shape', () {
    expect(client.subtitleExtension('subrip'), 'srt');
    expect(client.subtitleExtension('ass'), 'ass');
    expect(client.subtitleExtension('webvtt'), 'vtt');
    expect(client.subtitleExtension(null), 'srt');
    // Anything else is converted on the way out, so ask for a format every
    // player understands.
    expect(client.subtitleExtension('mov_text'), 'vtt');
  });
}

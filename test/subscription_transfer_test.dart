import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/models/youtube_channel.dart';
import 'package:fathom/services/subscription_transfer.dart';

void main() {
  group('Google Takeout CSV', () {
    test('parses the standard export', () {
      const csv = '''
Channel Id,Channel Url,Channel Title
UC7McHNOsrUL2fRxTB_xvgRQ,http://www.youtube.com/channel/UC7McHNOsrUL2fRxTB_xvgRQ,Johnny Carson
UCX6OQ3DkcsbYNE6H8uQQuVA,http://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA,MrBeast
''';
      final subs = SubscriptionTransfer.parseTakeoutCsv(csv);
      expect(subs.map((c) => c.id),
          ['UC7McHNOsrUL2fRxTB_xvgRQ', 'UCX6OQ3DkcsbYNE6H8uQQuVA']);
      expect(subs.first.title, 'Johnny Carson');
    });

    test('a channel title containing a comma survives', () {
      const csv =
          'UC7McHNOsrUL2fRxTB_xvgRQ,http://x/channel/UC7McHNOsrUL2fRxTB_xvgRQ,'
          '"Smith, Jane and Co"';
      final subs = SubscriptionTransfer.parseTakeoutCsv(csv);
      expect(subs.single.title, 'Smith, Jane and Co');
    });

    test('an escaped quote inside a title survives', () {
      const csv = 'UC7McHNOsrUL2fRxTB_xvgRQ,http://x,"The ""Best"" Channel"';
      final subs = SubscriptionTransfer.parseTakeoutCsv(csv);
      expect(subs.single.title, 'The "Best" Channel');
    });

    test('a localised header is skipped without matching on its text', () {
      // Non-English exports translate the header row.
      const csv = '''
Kanal-ID,Kanal-URL,Kanaltitel
UC7McHNOsrUL2fRxTB_xvgRQ,http://x,Johnny Carson
''';
      final subs = SubscriptionTransfer.parseTakeoutCsv(csv);
      expect(subs, hasLength(1));
      expect(subs.single.id, 'UC7McHNOsrUL2fRxTB_xvgRQ');
    });

    test('blank lines and junk rows are ignored, not imported', () {
      const csv = '''
Channel Id,Channel Url,Channel Title

not-a-channel,whatever,Nope
UC7McHNOsrUL2fRxTB_xvgRQ,http://x,Real
''';
      final subs = SubscriptionTransfer.parseTakeoutCsv(csv);
      expect(subs.map((c) => c.id), ['UC7McHNOsrUL2fRxTB_xvgRQ']);
    });
  });

  group('NewPipe JSON', () {
    test('parses a backup and skips other services', () {
      const json = '''
{
  "app_version": "0.27.0",
  "subscriptions": [
    {"service_id": 0, "url": "https://www.youtube.com/channel/UC7McHNOsrUL2fRxTB_xvgRQ", "name": "Johnny Carson"},
    {"service_id": 1, "url": "https://soundcloud.com/someone", "name": "Not YouTube"}
  ]
}
''';
      final subs = SubscriptionTransfer.parseNewPipeJson(json);
      expect(subs, hasLength(1));
      expect(subs.single.id, 'UC7McHNOsrUL2fRxTB_xvgRQ');
      expect(subs.single.title, 'Johnny Carson');
    });

    test('handle URLs are rejected rather than guessed at', () {
      // /@name cannot be resolved to an id without a network lookup.
      const json =
          '{"subscriptions":[{"service_id":0,"url":"https://www.youtube.com/@johnnycarson","name":"JC"}]}';
      expect(SubscriptionTransfer.parseNewPipeJson(json), isEmpty);
    });

    test('malformed json yields nothing instead of throwing', () {
      expect(SubscriptionTransfer.parseNewPipeJson('{oh no'), isEmpty);
    });
  });

  test('format is detected from content, not the file name', () {
    const csv = 'UC7McHNOsrUL2fRxTB_xvgRQ,http://x,Name';
    const json =
        '{"subscriptions":[{"service_id":0,"url":"https://www.youtube.com/channel/UC7McHNOsrUL2fRxTB_xvgRQ","name":"N"}]}';
    expect(SubscriptionTransfer.parse(csv), hasLength(1));
    expect(SubscriptionTransfer.parse(json), hasLength(1));
  });

  test('duplicates collapse', () {
    const csv = '''
UC7McHNOsrUL2fRxTB_xvgRQ,http://x,Name
UC7McHNOsrUL2fRxTB_xvgRQ,http://x,Name Again
''';
    expect(SubscriptionTransfer.parseTakeoutCsv(csv), hasLength(1));
  });

  test('export round-trips back through the importer', () {
    const channels = [
      YoutubeChannel(
          id: 'UC7McHNOsrUL2fRxTB_xvgRQ', title: 'Johnny Carson', logoUrl: ''),
      YoutubeChannel(
          id: 'UCX6OQ3DkcsbYNE6H8uQQuVA', title: 'MrBeast', logoUrl: ''),
    ];
    final out = SubscriptionTransfer.exportNewPipeJson(channels);
    // Shape NewPipe expects.
    final decoded = jsonDecode(out) as Map;
    expect(decoded['subscriptions'], hasLength(2));
    expect((decoded['subscriptions'] as List).first['service_id'], 0);

    final back = SubscriptionTransfer.parseNewPipeJson(out);
    expect(back.map((c) => c.id), channels.map((c) => c.id));
    expect(back.map((c) => c.title), channels.map((c) => c.title));
  });
}

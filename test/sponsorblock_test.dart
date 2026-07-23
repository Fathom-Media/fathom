import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/services/sponsorblock.dart';

/// Serves a canned response so the parsing is tested without the network.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final String body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

// ignore: library_private_types_in_public_api
SponsorBlock clientFor(_Adapter a) =>
    SponsorBlock(dio: Dio()..httpClientAdapter = a);

void main() {
  // The real shape, copied from a live response.
  const real = '''
[{"category":"sponsor","actionType":"skip","segment":[64.215,86.885],
  "UUID":"abc","videoDuration":1358.042,"locked":0,"votes":7,"description":""},
 {"category":"outro","actionType":"skip","segment":[1268.0,1349.6],
  "UUID":"def","videoDuration":1358.042,"locked":0,"votes":4,"description":""}]
''';

  test('parses real segments', () async {
    final a = _Adapter(200, real);
    final segs = await clientFor(a)
        .segments('vid', categories: {SponsorCategory.sponsor, SponsorCategory.outro});

    expect(segs, hasLength(2));
    expect(segs.first.category, SponsorCategory.sponsor);
    expect(segs.first.start, const Duration(milliseconds: 64215));
    expect(segs.first.end, const Duration(milliseconds: 86885));
    expect(segs.first.votes, 7);
    expect(segs.first.contains(const Duration(seconds: 70)), isTrue);
    expect(segs.first.contains(const Duration(seconds: 90)), isFalse);
  });

  test('404 means no submissions, not a failure', () async {
    // Most videos have nothing, and the API says so with a 404. Treating that
    // as an error would log noise on nearly every video.
    final segs = await clientFor(_Adapter(404, 'Not Found'))
        .segments('vid', categories: {SponsorCategory.sponsor});
    expect(segs, isEmpty);
  });

  test('a server error never breaks playback', () async {
    final segs = await clientFor(_Adapter(500, 'boom'))
        .segments('vid', categories: {SponsorCategory.sponsor});
    expect(segs, isEmpty);
  });

  test('asks only for the categories that are enabled', () async {
    final a = _Adapter(200, '[]');
    await clientFor(a).segments('vid',
        categories: {SponsorCategory.sponsor, SponsorCategory.filler});
    final sent = jsonDecode(a.last!.queryParameters['categories'] as String);
    expect(sent, containsAll(['sponsor', 'filler']));
    expect(sent, isNot(contains('outro')));
    expect(a.last!.queryParameters['videoID'], 'vid');
  });

  test('no categories enabled means no request at all', () async {
    final a = _Adapter(200, real);
    expect(await clientFor(a).segments('vid'), isEmpty);
    expect(a.last, isNull, reason: 'it should not call out for nothing');
  });

  test('poi_highlight is not treated as something to skip', () async {
    // It marks a point to jump TO. Skipping it would leap past the highlight.
    const poi = '''
[{"category":"poi_highlight","actionType":"poi","segment":[10.0,10.0],
  "UUID":"x","votes":5}]
''';
    final segs = await clientFor(_Adapter(200, poi))
        .segments('vid', categories: {SponsorCategory.sponsor});
    expect(segs, isEmpty);
  });

  test('malformed or reversed segments are dropped', () async {
    const bad = '''
[{"category":"sponsor","actionType":"skip","segment":[50.0,50.0],"UUID":"a","votes":1},
 {"category":"sponsor","actionType":"skip","segment":[80.0,20.0],"UUID":"b","votes":1},
 {"category":"nonsense","actionType":"skip","segment":[1.0,2.0],"UUID":"c","votes":1}]
''';
    // Zero-length does nothing; reversed would seek backwards forever; an
    // unknown category is one YouTube added that we don't model yet.
    final segs = await clientFor(_Adapter(200, bad))
        .segments('vid', categories: {SponsorCategory.sponsor});
    expect(segs, isEmpty);
  });

  test('segments come back in order', () async {
    const unordered = '''
[{"category":"outro","actionType":"skip","segment":[900.0,950.0],"UUID":"b","votes":1},
 {"category":"sponsor","actionType":"skip","segment":[10.0,20.0],"UUID":"a","votes":1}]
''';
    final segs = await clientFor(_Adapter(200, unordered)).segments('vid',
        categories: {SponsorCategory.sponsor, SponsorCategory.outro});
    expect(segs.map((s) => s.uuid), ['a', 'b']);
  });
}

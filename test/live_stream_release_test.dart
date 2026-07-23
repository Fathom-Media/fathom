import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fathom/api/jellyfin_client.dart';

/// Records what the client sends instead of hitting a server.
class _CaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{}', 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

/// Releasing a Live TV tuner is not best-effort housekeeping: an HDHomeRun has
/// two, Jellyfin holds one open until told the stream ended, and a missed
/// release means every later tune-in 500s until the server restarts.
void main() {
  late _CaptureAdapter adapter;
  late JellyfinClient client;

  setUp(() {
    adapter = _CaptureAdapter();
    client = JellyfinClient(
        deviceId: 'dev-1', httpClient: Dio()..httpClientAdapter = adapter);
  });

  test('Stopped carries the ids that identify the live session', () async {
    await client.reportPlaybackStopped(
      baseUrl: 'http://jf',
      token: 't',
      itemId: 'item-1',
      positionTicks: 123,
      liveStreamId: 'ls-abc',
      playSessionId: 'ps-xyz',
    );

    expect(adapter.requests, hasLength(1));
    final req = adapter.requests.single;
    expect(req.path, 'http://jf/Sessions/Playing/Stopped');
    final body = req.data as Map;
    // Without these the server never learns which live session ended, so it
    // keeps the tuner and the transcode running. This is the whole bug.
    expect(body['LiveStreamId'], 'ls-abc');
    expect(body['PlaySessionId'], 'ps-xyz');
    expect(body['ItemId'], 'item-1');
    expect(body['PositionTicks'], 123);
  });

  test('ordinary video omits the live ids rather than sending nulls', () async {
    await client.reportPlaybackStopped(
      baseUrl: 'http://jf',
      token: 't',
      itemId: 'item-1',
      positionTicks: 9,
    );
    final body = adapter.requests.single.data as Map;
    expect(body.containsKey('LiveStreamId'), isFalse);
    expect(body.containsKey('PlaySessionId'), isFalse);
  });

  test('closeLiveStream posts the id the server expects', () async {
    await client.closeLiveStream(
      baseUrl: 'http://jf',
      token: 't',
      liveStreamId: 'ls-abc',
      playSessionId: 'ps-xyz',
    );

    final paths = adapter.requests.map((r) => r.path).toList();
    expect(paths, contains('http://jf/LiveStreams/Close'));
    final close = adapter.requests
        .firstWhere((r) => r.path.endsWith('/LiveStreams/Close'));
    expect(close.queryParameters['liveStreamId'], 'ls-abc');

    // /Videos/ActiveEncodings is not part of the Jellyfin API any more; it
    // 404'd on every call and released nothing.
    expect(paths.where((p) => p.contains('ActiveEncodings')), isEmpty);
  });

  test('a failing close is swallowed, not thrown at the caller', () async {
    final failing = Dio()..httpClientAdapter = _FailingAdapter();
    final c = JellyfinClient(deviceId: 'd', httpClient: failing);
    // It runs while a screen is being torn down; a throw there would abort the
    // rest of the teardown.
    await expectLater(
      c.closeLiveStream(baseUrl: 'http://jf', token: 't', liveStreamId: 'x'),
      completes,
    );
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException(requestOptions: options, message: 'boom');
  }

  @override
  void close({bool force = false}) {}
}

import 'dart:async';

import '../api/jellyfin_client.dart';
import '../models/session.dart';

/// One open Live TV stream, and what it takes to hand the tuner back.
class OpenLiveStream {
  final JellyfinClient client;
  final Session session;
  final String liveStreamId;
  final String? playSessionId;

  const OpenLiveStream({
    required this.client,
    required this.session,
    required this.liveStreamId,
    this.playSessionId,
  });
}

/// Live TV streams currently open on the server.
///
/// A tuner is a physical resource: an HDHomeRun has two, and Jellyfin holds one
/// open until it is told the stream ended. Miss that and the next tune-in fails
/// with a 500 ("simultaneous stream limit reached") until the server is
/// restarted — which is exactly what kept happening.
///
/// The player releases its own stream when you leave it. This registry exists
/// for the case nothing else covers: quitting the app outright while a channel
/// is playing, where no screen teardown ever runs.
class LiveStreams {
  LiveStreams._();

  static final Set<OpenLiveStream> _open = <OpenLiveStream>{};

  static void register(OpenLiveStream stream) => _open.add(stream);

  static void unregister(String liveStreamId) =>
      _open.removeWhere((s) => s.liveStreamId == liveStreamId);

  /// Hands every open tuner back. Errors are swallowed deliberately: this runs
  /// while the app is quitting, and a throw would abandon the remaining
  /// streams, leaking the very tuners it exists to free.
  static Future<void> closeAll() async {
    final streams = _open.toList();
    _open.clear();
    for (final s in streams) {
      try {
        await s.client.closeLiveStream(
          baseUrl: s.session.baseUrl,
          token: s.session.accessToken,
          liveStreamId: s.liveStreamId,
          playSessionId: s.playSessionId,
        );
      } catch (_) {}
    }
  }
}

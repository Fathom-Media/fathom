import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../services/mpris.dart';
import 'audio_player.dart';
import 'session_controller.dart';

/// Wires the MPRIS desktop-media integration to the app-wide music player, so
/// the panel applet, media keys and lock screen control it. Linux only; null
/// elsewhere. Kept alive by a watch in the app root.
final mprisProvider = Provider<MprisService?>((ref) {
  if (!Platform.isLinux) return null;
  final mpris = MprisService();
  final player = ref.read(audioPlayerProvider);
  final controller = ref.read(audioControllerProvider.notifier);

  mpris.onPlayPause = controller.togglePlay;
  mpris.onPlay = player.play;
  mpris.onPause = player.pause;
  mpris.onStop = player.stop;
  mpris.onNext = controller.next;
  mpris.onPrevious = controller.previous;
  mpris.onSeek = (offsetUs) => player
      .seek(player.state.position + Duration(microseconds: offsetUs));
  mpris.onSetPosition =
      (posUs) => player.seek(Duration(microseconds: posUs));
  mpris.onSetVolume =
      (v) => player.setVolume((v * 100).clamp(0.0, 100.0));

  unawaited(mpris.init());

  void push() {
    final st = ref.read(audioControllerProvider);
    final current = st.current;
    final status = current == null
        ? 'Stopped'
        : (player.state.playing ? 'Playing' : 'Paused');
    mpris.update(
      status: status,
      metadata: current == null ? {} : _metadataFor(ref, current),
      volume: (player.state.volume / 100).clamp(0.0, 1.0),
      positionUs: player.state.position.inMicroseconds,
      canNext: st.queue.length > 1,
      canPrev: st.queue.length > 1,
    );
  }

  // Track change / queue change.
  ref.listen(audioControllerProvider, (_, _) => push());
  // Playing/paused transitions.
  final playingSub = player.stream.playing.listen((_) => push());
  // Keep the reported Position roughly live (no D-Bus emit for position).
  final posSub = player.stream.position
      .listen((p) => mpris.update(positionUs: p.inMicroseconds));

  ref.onDispose(() {
    playingSub.cancel();
    posSub.cancel();
    unawaited(mpris.dispose());
  });

  push();
  return mpris;
});

Map<String, DBusValue> _metadataFor(Ref ref, BaseItemDto t) {
  final session = ref.read(sessionControllerProvider).asData?.value;
  final artists = t.artists.isNotEmpty
      ? t.artists
      : (t.albumArtist != null ? [t.albumArtist!] : const <String>[]);
  final lengthUs = (t.runTimeTicks ?? 0) ~/ 10;
  // A stable, valid object path for the track id.
  final safeId = t.id.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  final meta = <String, DBusValue>{
    'mpris:trackid': DBusObjectPath('/app/fathom/track/$safeId'),
    'xesam:title': DBusString(t.name),
    if (lengthUs > 0) 'mpris:length': DBusInt64(lengthUs),
    if (artists.isNotEmpty) 'xesam:artist': DBusArray.string(artists),
    if (t.album != null) 'xesam:album': DBusString(t.album!),
  };
  if (session != null) {
    final imgId = t.albumId ?? t.id;
    final tag = t.albumPrimaryImageTag ?? t.primaryImageTag;
    // Auth travels in the URL: the desktop fetches art directly, no headers.
    meta['mpris:artUrl'] = DBusString(
        '${session.baseUrl}/Items/$imgId/Images/Primary'
        '?api_key=${session.accessToken}&maxHeight=300'
        '${tag != null ? '&tag=$tag' : ''}');
  }
  return meta;
}

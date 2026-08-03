import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../services/mpris.dart';
import 'audio_player.dart';
import 'media_session.dart';
import 'session_controller.dart';

/// Wires the MPRIS desktop-media integration to the app-wide music player, so
/// the panel applet, media keys and lock screen control it. Linux only; null
/// elsewhere. Kept alive by a watch in the app root.
final mprisProvider = Provider<MprisService?>((ref) {
  if (!Platform.isLinux) return null;
  final mpris = MprisService();
  final player = ref.read(audioPlayerProvider);
  final controller = ref.read(audioControllerProvider.notifier);

  // A video on screen takes over the controls; otherwise the music player does.
  VideoMediaSession? video() => ref.read(videoMediaSessionProvider);

  mpris.onPlayPause = () async {
    final v = video();
    if (v != null) return v.playing ? v.onPause() : v.onPlay();
    return controller.togglePlay();
  };
  mpris.onPlay = () async => (video()?.onPlay ?? player.play)();
  mpris.onPause = () async => (video()?.onPause ?? player.pause)();
  mpris.onStop = () async => (video()?.onStop ?? player.stop)();
  mpris.onNext = () async {
    final v = video();
    if (v != null) return v.onNext?.call();
    return controller.next();
  };
  mpris.onPrevious = () async {
    final v = video();
    if (v != null) return v.onPrevious?.call();
    return controller.previous();
  };
  mpris.onSeek = (offsetUs) async {
    final v = video();
    if (v != null) {
      return v.onSeek(v.position + Duration(microseconds: offsetUs));
    }
    return player.seek(player.state.position + Duration(microseconds: offsetUs));
  };
  mpris.onSetPosition = (posUs) async {
    final v = video();
    if (v != null) return v.onSeek(Duration(microseconds: posUs));
    return player.seek(Duration(microseconds: posUs));
  };
  mpris.onSetVolume =
      (v) => player.setVolume((v * 100).clamp(0.0, 100.0));

  unawaited(mpris.init());

  void push() {
    final v = video();
    // Prefer whatever is actually playing: a paused or backgrounded video must
    // not keep holding the controls while music/radio is playing.
    if (v != null && (v.playing || !player.state.playing)) {
      mpris.update(
        status: v.playing ? 'Playing' : 'Paused',
        metadata: _videoMetadata(v),
        positionUs: v.position.inMicroseconds,
        canNext: v.canNext,
        canPrev: v.canPrev,
      );
      return;
    }
    final st = ref.read(audioControllerProvider);
    // Internet radio: the music player has no queue track, so present the
    // station (with its live ICY "now playing", if any) instead.
    if (st.isRadio && st.radioStation != null) {
      mpris.update(
        status: player.state.playing ? 'Playing' : 'Paused',
        metadata: _radioMetadata(st),
        canNext: false,
        canPrev: false,
      );
      return;
    }
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

  // Music/radio track change.
  ref.listen(audioControllerProvider, (_, _) => push());
  // Video takes over / hands back, and its play/position updates.
  ref.listen(videoMediaSessionProvider, (_, _) => push());
  // Playing/paused transitions of the music player.
  final playingSub = player.stream.playing.listen((_) => push());
  // Keep the reported music Position live (no D-Bus emit for position); while a
  // video owns the session its own position updates drive push() instead.
  final posSub = player.stream.position.listen((p) {
    if (video() == null) mpris.update(positionUs: p.inMicroseconds);
  });
  // Self-heal: re-assert the authoritative state every second so a missed
  // play/pause event (notably across the video->music handoff) can never leave
  // the desktop stuck on a stale status. update() de-dupes, so this only emits a
  // D-Bus change when something actually drifted — silent otherwise.
  final syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => push());

  ref.onDispose(() {
    playingSub.cancel();
    posSub.cancel();
    syncTimer.cancel();
    unawaited(mpris.dispose());
  });

  push();
  return mpris;
});

Map<String, DBusValue> _radioMetadata(AudioState st) {
  final s = st.radioStation!;
  final icy = st.radioTitle;
  final hasIcy = icy != null && icy.isNotEmpty;
  final art = (st.radioArtwork != null && st.radioArtwork!.isNotEmpty)
      ? st.radioArtwork!
      : (s.favicon ?? '');
  final tags = s.tags;
  final genre = (tags != null && tags.trim().isNotEmpty) ? tags : 'Live radio';
  final meta = <String, DBusValue>{
    'mpris:trackid': DBusObjectPath('/app/fathom/radio'),
    'xesam:title': DBusString(hasIcy ? icy : s.name),
    // With ICY metadata the station name reads as the "artist"; otherwise fall
    // back to the station's genre/tags.
    'xesam:artist': DBusArray.string([hasIcy ? s.name : genre]),
  };
  if (art.isNotEmpty) meta['mpris:artUrl'] = DBusString(art);
  return meta;
}

Map<String, DBusValue> _videoMetadata(VideoMediaSession v) {
  final meta = <String, DBusValue>{
    'mpris:trackid': DBusObjectPath('/app/fathom/video'),
    'xesam:title': DBusString(v.title),
    if (v.duration > Duration.zero)
      'mpris:length': DBusInt64(v.duration.inMicroseconds),
    if (v.subtitle != null && v.subtitle!.isNotEmpty)
      'xesam:artist': DBusArray.string([v.subtitle!]),
  };
  if (v.artUrl != null) meta['mpris:artUrl'] = DBusString(v.artUrl!);
  return meta;
}

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

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smtc_windows/smtc_windows.dart' show MusicMetadata;

import '../models/base_item.dart';
import '../services/smtc.dart';
import 'audio_player.dart';
import 'media_session.dart';
import 'session_controller.dart';

/// Wires Windows System Media Transport Controls to the app-wide music player,
/// so media keys, Bluetooth, and tools like KDE Connect control it. Windows
/// only; null elsewhere. Mirrors [mprisProvider] on Linux. Kept alive by a watch
/// in the app root.
final smtcProvider = Provider<SmtcService?>((ref) {
  if (!Platform.isWindows) return null;
  final smtc = SmtcService();
  final player = ref.read(audioPlayerProvider);
  final controller = ref.read(audioControllerProvider.notifier);

  // A video on screen takes over the controls; otherwise the music player does.
  VideoMediaSession? video() => ref.read(videoMediaSessionProvider);

  smtc.onPlay = () async => (video()?.onPlay ?? player.play)();
  smtc.onPause = () async => (video()?.onPause ?? player.pause)();
  smtc.onStop = () async => (video()?.onStop ?? player.stop)();
  smtc.onNext = () async {
    final v = video();
    if (v != null) return v.onNext?.call();
    return controller.next();
  };
  smtc.onPrevious = () async {
    final v = video();
    if (v != null) return v.onPrevious?.call();
    return controller.previous();
  };

  unawaited(smtc.init());

  void push() {
    final v = video();
    // Prefer whatever is actually playing: a paused/backgrounded video must not
    // keep holding the controls while music is playing.
    if (v != null && (v.playing || !player.state.playing)) {
      smtc.update(
        status: v.playing ? 'Playing' : 'Paused',
        metadata: MusicMetadata(
          title: v.title,
          artist: v.subtitle,
          thumbnail: v.artUrl,
        ),
        canNext: v.canNext,
        canPrev: v.canPrev,
      );
      return;
    }
    final st = ref.read(audioControllerProvider);
    // Internet radio: no queue track, so present the station + live ICY title.
    if (st.isRadio && st.radioStation != null) {
      final s = st.radioStation!;
      final icy = st.radioTitle;
      final hasIcy = icy != null && icy.isNotEmpty;
      final art = (st.radioArtwork != null && st.radioArtwork!.isNotEmpty)
          ? st.radioArtwork
          : s.favicon;
      // Always a non-empty artist so it overwrites a previous track's (a null/
      // empty field can linger on the OS control): the station name alongside
      // the live song, or the genre/"Live radio" when there's no song title.
      final tags = s.tags;
      final genre = (tags != null && tags.trim().isNotEmpty) ? tags : 'Live radio';
      smtc.update(
        status: player.state.playing ? 'Playing' : 'Paused',
        metadata: MusicMetadata(
          title: hasIcy ? icy : s.name,
          artist: hasIcy ? s.name : genre,
          thumbnail: art,
        ),
        canNext: false,
        canPrev: false,
      );
      return;
    }
    final current = st.current;
    final status = current == null
        ? 'Stopped'
        : (player.state.playing ? 'Playing' : 'Paused');
    smtc.update(
      status: status,
      metadata:
          current == null ? const MusicMetadata() : _metadataFor(ref, current),
      canNext: st.queue.length > 1,
      canPrev: st.queue.length > 1,
    );
  }

  // Music track/queue change.
  ref.listen(audioControllerProvider, (_, _) => push());
  // Video takes over / hands back, and its play/position updates.
  ref.listen(videoMediaSessionProvider, (_, _) => push());
  // Playing/paused transitions of the music player.
  final playingSub = player.stream.playing.listen((_) => push());
  // Self-heal: re-assert the authoritative state every second so a missed event
  // (e.g. across the video->music handoff) can't leave the controls stale.
  // update() de-dupes, so this is a no-op when nothing changed.
  final syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => push());

  ref.onDispose(() {
    playingSub.cancel();
    syncTimer.cancel();
    unawaited(smtc.dispose());
  });

  push();
  return smtc;
});

MusicMetadata _metadataFor(Ref ref, BaseItemDto t) {
  final session = ref.read(sessionControllerProvider).asData?.value;
  final artist = t.artists.isNotEmpty
      ? t.artists.join(', ')
      : (t.albumArtist ?? '');
  String? thumbnail;
  if (session != null) {
    final imgId = t.albumId ?? t.id;
    final tag = t.albumPrimaryImageTag ?? t.primaryImageTag;
    // Auth travels in the URL: SMTC fetches the thumbnail directly, no headers.
    thumbnail = '${session.baseUrl}/Items/$imgId/Images/Primary'
        '?api_key=${session.accessToken}&maxHeight=300'
        '${tag != null ? '&tag=$tag' : ''}';
  }
  return MusicMetadata(
    title: t.name,
    artist: artist.isNotEmpty ? artist : null,
    album: t.album,
    albumArtist: t.albumArtist,
    thumbnail: thumbnail,
  );
}

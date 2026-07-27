import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../services/secure_http.dart';

import 'audio_handler.dart';
import 'cast.dart';
import '../api/jellyfin_client.dart';
import '../models/base_item.dart';
import '../models/radio_station.dart';
import '../models/session.dart';
import '../services/live_players.dart';
import 'providers.dart';
import 'session_controller.dart';
import 'volume_sync.dart';
import 'preferences.dart';

/// A single, app-wide audio player (separate from the video player).
final audioPlayerProvider = Provider<Player>((ref) {
  final player = Player();
  // Music shares the app's volume with video. One app, one pair of speakers:
  // a level set for a late-night episode should mean the same for an album.
  final volume = VolumeSync(
    player: player,
    read: () => ref.read(preferencesProvider).asData?.value.volume ?? 100,
    write: (v) =>
        ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(volume: v)),
  )..attach();
  // This player is created early (mini player / radio), often before the async
  // preferences have loaded — so attach() above read the default (100, full)
  // while the slider shows the remembered level. Re-apply the stored volume the
  // moment preferences arrive so audio actually plays at that level.
  if (ref.read(preferencesProvider).asData == null) {
    late final ProviderSubscription<AsyncValue<Prefs>> sub;
    sub = ref.listen(preferencesProvider, (_, next) {
      if (next.asData != null) {
        volume.reapply();
        sub.close();
      }
    });
  }
  // Registered so quitting with music playing tears mpv down before the engine
  // goes: this provider's onDispose never runs, because nothing disposes the
  // root container at process exit.
  LivePlayers.add(player);
  ref.onDispose(() {
    volume.dispose();
    LivePlayers.remove(player);
    player.dispose();
  });
  return player;
});

class AudioState {
  final List<BaseItemDto> queue;
  final BaseItemDto? current;
  final bool shuffle;
  final PlaylistMode repeat;
  // Internet radio: when [radioStation] is set, the player is on a live radio
  // stream (not the music queue), and the UI shows a radio presentation (no
  // seek/skip). [radioTitle] is the live ICY "now playing" line, if any.
  // [radioArtwork] is a per-song album-art URL when the stream sends one
  // (iHeart-style `amgArtworkURL`); otherwise null and the UI shows the logo.
  final RadioStation? radioStation;
  final String? radioTitle;
  final String? radioArtwork;
  // Live time-shift: [radioSeekable] is true when the stream supports scrubbing
  // (rewind/skip). [radioBehindLive] is how far behind the live edge playback is
  // (Duration.zero = live). [radioWindow] is how far back you can currently go
  // (the buffered window), for drawing the scrub bar.
  final bool radioSeekable;
  final Duration radioBehindLive;
  final Duration radioWindow;

  const AudioState({
    this.queue = const [],
    this.current,
    this.shuffle = false,
    this.repeat = PlaylistMode.none,
    this.radioStation,
    this.radioTitle,
    this.radioArtwork,
    this.radioSeekable = false,
    this.radioBehindLive = Duration.zero,
    this.radioWindow = Duration.zero,
  });

  bool get hasTrack => current != null;
  bool get isRadio => radioStation != null;
  // "At live" once we're within a couple of seconds of the edge.
  bool get radioAtLive => radioBehindLive.inMilliseconds < 2500;

  AudioState copyWith({
    List<BaseItemDto>? queue,
    BaseItemDto? current,
    bool? shuffle,
    PlaylistMode? repeat,
    Object? radioStation = _unset,
    Object? radioTitle = _unset,
    Object? radioArtwork = _unset,
    bool? radioSeekable,
    Duration? radioBehindLive,
    Duration? radioWindow,
  }) =>
      AudioState(
        queue: queue ?? this.queue,
        current: current ?? this.current,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        radioStation: radioStation == _unset
            ? this.radioStation
            : radioStation as RadioStation?,
        radioTitle:
            radioTitle == _unset ? this.radioTitle : radioTitle as String?,
        radioArtwork: radioArtwork == _unset
            ? this.radioArtwork
            : radioArtwork as String?,
        radioSeekable: radioSeekable ?? this.radioSeekable,
        radioBehindLive: radioBehindLive ?? this.radioBehindLive,
        radioWindow: radioWindow ?? this.radioWindow,
      );
}

const _unset = Object();

/// Owns the queue, mirrors the player's track index for the UI, and reports
/// playback to the server (now-playing + play counts, i.e. scrobbling).
class AudioController extends Notifier<AudioState> {
  Player get _player => ref.read(audioPlayerProvider);
  Timer? _progressTimer;
  Timer? _radioIcyTimer; // polls the live ICY "now playing" while on radio
  Timer? _radioTick; // 1s ticker for live time-shift (behind-live / seekable)
  // Live edge in playback time: advances by wall-clock every tick, so pausing or
  // rewinding leaves playback behind it. Reset on tune / go-live.
  Duration _radioEdge = Duration.zero;
  DateTime? _radioTickWall;
  static const _radioMaxWindow = Duration(minutes: 30);
  String? _artLookupKey; // the song title whose artwork we're currently resolving
  String? _reportedId;
  int _lastPositionTicks = 0;
  final Map<String, BaseItemDto> _byId = {};
  final _random = Random();
  // The OS media session (mobile only); null on desktop or if init failed.
  FathomAudioHandler? _handler;

  // The stream URL always contains /Audio/{itemId}/stream — resolve the current
  // track by URL so it stays correct even after shuffling reorders the queue.
  static final _idPattern = RegExp(r'/Audio/([^/]+)/stream');
  String? _itemIdFromUri(String uri) => _idPattern.firstMatch(uri)?.group(1);

  @override
  AudioState build() {
    // Hand off to / back from a Chromecast. On connect, pause local so audio
    // isn't playing in two places. On disconnect, resume local from the track
    // and position the receiver reached (like Spotify/YT Music), so stopping
    // the cast continues seamlessly on the phone.
    ref.listen(castControllerProvider.select((s) => s.casting), (prev, next) {
      if (next == true) {
        _player.pause();
      } else if (prev == true) {
        final c = ref.read(castControllerProvider);
        _resumeLocalFromCast(c.currentUrl, c.positionMs, c.playing);
      }
    });
    // Follow the receiver's current queue item (it auto-advances / Skip on the
    // device), so the app's now-playing display tracks what's actually playing.
    ref.listen(castControllerProvider.select((s) => s.currentUrl), (_, url) {
      if (url == null) return;
      final id = RegExp(r'/Audio/([0-9a-fA-F]+)/').firstMatch(url)?.group(1);
      if (id == null || id == state.current?.id) return;
      final matches = state.queue.where((t) => t.id == id);
      if (matches.isNotEmpty) state = state.copyWith(current: matches.first);
    });
    // Wire the OS media session (mobile). The handler owns no player, so route
    // its transport buttons back into ours; state is pushed the other way below.
    _handler = ref.read(audioHandlerProvider);
    final h = _handler;
    if (h != null) {
      h.onPlay = _player.play;
      h.onPause = _player.pause;
      h.onNext = _player.next;
      h.onPrevious = _player.previous;
      h.onSeek = _player.seek;
      h.onStop = () async => _player.stop();
    }

    final subPlaylist = _player.stream.playlist.listen((pl) {
      // Keep the visible queue in the player's real order (matters once shuffle
      // or a reorder has rearranged things), and follow the current track.
      final ordered = pl.medias
          .map((m) => _byId[_itemIdFromUri(m.uri)])
          .whereType<BaseItemDto>()
          .toList();
      final id = (pl.index >= 0 && pl.index < pl.medias.length)
          ? _itemIdFromUri(pl.medias[pl.index].uri)
          : null;
      final track = id != null ? _byId[id] : null;
      if (track != null && track.id != state.current?.id) {
        _reportStopped();
        _lastPositionTicks = 0;
        _reportStart(track.id);
        state = state.copyWith(
            queue: ordered.isNotEmpty ? ordered : state.queue, current: track);
        _pushNowPlaying();
      } else if (ordered.isNotEmpty) {
        state = state.copyWith(queue: ordered);
      }
    });
    final subPosition = _player.stream.position.listen((p) {
      _lastPositionTicks = p.inMicroseconds * 10;
    });
    // Mirror transport state to the media session. Position is extrapolated by
    // the OS between updates, so pushing on play/pause/buffer/duration changes
    // (plus the 10s progress tick) keeps the notification honest.
    StreamSubscription<bool>? subPlaying, subBuffering;
    StreamSubscription<Duration>? subDuration;
    if (h != null) {
      subPlaying = _player.stream.playing.listen((_) => _pushPlaybackState());
      subBuffering = _player.stream.buffering.listen((_) => _pushPlaybackState());
      // Re-publish now-playing once the real duration is known.
      subDuration = _player.stream.duration.listen((_) => _pushNowPlaying());
    }
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _reportProgress();
      _pushPlaybackState();
    });
    ref.onDispose(() {
      subPlaylist.cancel();
      subPosition.cancel();
      subPlaying?.cancel();
      subBuffering?.cancel();
      subDuration?.cancel();
      _progressTimer?.cancel();
      _radioIcyTimer?.cancel();
      _radioTick?.cancel();
      _reportStopped();
    });
    return const AudioState();
  }

  /// Publish the current track's metadata to the OS media session.
  void _pushNowPlaying() {
    // Radio publishes its own MediaItem via _pushRadioNowPlaying; don't let a
    // stream duration/playlist event push a stale music track over it.
    if (state.isRadio) return;
    final h = _handler;
    final t = state.current;
    if (h == null || t == null) return;
    final c = _ctx();
    Uri? art;
    if (c != null) {
      // A song usually has no image of its own; the album carries the art. Fall
      // back to it, matching MediaImage's resolution.
      String? imgItemId, imgTag;
      if (t.primaryImageTag != null) {
        imgItemId = t.id;
        imgTag = t.primaryImageTag;
      } else if (t.albumPrimaryImageTag != null && t.albumId != null) {
        imgItemId = t.albumId;
        imgTag = t.albumPrimaryImageTag;
      }
      if (imgItemId != null) {
        art = Uri.tryParse(c.client.imageUrl(
          baseUrl: c.session.baseUrl,
          itemId: imgItemId,
          tag: imgTag,
          maxHeight: 512,
        ));
      }
    }
    final dur = _player.state.duration;
    h.setNowPlaying(MediaItem(
      id: t.id,
      title: t.name,
      artist: t.albumArtist ??
          (t.artists.isNotEmpty ? t.artists.join(', ') : null),
      album: t.album,
      duration: dur > Duration.zero ? dur : null,
      artUri: art,
    ));
  }

  /// Publish current transport state (playing/paused, position, buffered).
  void _pushPlaybackState() {
    final h = _handler;
    if (h == null) return;
    final s = _player.state;
    h.setPlayback(
      playing: s.playing,
      buffering: s.buffering,
      position: s.position,
      buffered: s.buffer,
      speed: s.rate,
    );
  }

  ({Session session, JellyfinClient client})? _ctx() {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return null;
    return (session: session, client: ref.read(jellyfinClientProvider));
  }

  Future<void> playQueue(List<BaseItemDto> tracks, int startIndex,
      {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    final c = _ctx();
    if (c == null) return;
    _radioIcyTimer?.cancel(); // leaving radio for the music queue
    _radioTick?.cancel();
    final medias = tracks
        .map((t) => Media(c.client.audioStreamUrl(
              baseUrl: c.session.baseUrl,
              itemId: t.id,
              token: c.session.accessToken,
            )))
        .toList();
    _reportStopped();
    _byId
      ..clear()
      ..addEntries(tracks.map((t) => MapEntry(t.id, t)));
    // Shuffle: start on a RANDOM track (not always the first) and turn the
    // player's shuffle mode on. A normal play starts at [startIndex] in order,
    // and explicitly turns shuffle off so the two buttons are true opposites.
    final index =
        (shuffle && tracks.length > 1) ? _random.nextInt(tracks.length) : startIndex;
    state = state.copyWith(
        queue: tracks,
        current: tracks[index],
        shuffle: shuffle,
        radioStation: null,
        radioTitle: null,
        radioSeekable: false,
        radioBehindLive: Duration.zero,
        radioWindow: Duration.zero);
    await _player.open(Playlist(medias, index: index));
    await _player.setShuffle(shuffle);
    _lastPositionTicks = 0;
    _reportStart(tracks[index].id);
    // Publish to the media session right away so its foreground notification
    // appears promptly (and Android sees startForeground before its deadline).
    _pushNowPlaying();
    _pushPlaybackState();
  }

  /// Play an internet-radio station: opens its live stream (replacing the music
  /// queue), switches the UI to the radio presentation, and polls ICY metadata.
  Future<void> playStation(RadioStation s) async {
    _radioIcyTimer?.cancel();
    _radioTick?.cancel();
    _reportStopped(); // no Jellyfin scrobble for radio
    _reportedId = null;
    state = state.copyWith(
      radioStation: s,
      radioTitle: null,
      radioArtwork: null,
      radioSeekable: false,
      radioBehindLive: Duration.zero,
      radioWindow: Duration.zero,
    );
    _radioEdge = Duration.zero;
    _radioTickWall = null;
    await _configureRadioBuffer();
    await _player.open(Media(s.url));
    _pushRadioNowPlaying(s, null);
    _pushPlaybackState();
    _startIcyPolling();
    _startRadioTick();
  }

  /// Enable a back-buffer + forced seeking so we can pause (and keep buffering)
  /// and, where the stream allows, rewind/skip within the buffered window.
  Future<void> _configureRadioBuffer() async {
    try {
      final p = _player.platform as dynamic;
      const bytes = 96 * 1024 * 1024; // ~96 MiB each way (several minutes of audio)
      await p.setProperty('force-seekable', 'yes');
      await p.setProperty('demuxer-max-bytes', '$bytes');
      await p.setProperty('demuxer-max-back-bytes', '$bytes');
    } catch (_) {}
  }

  /// Stop radio and leave radio mode (back to whatever music context existed).
  Future<void> stopRadio() async {
    _radioIcyTimer?.cancel();
    _radioTick?.cancel();
    await _player.stop();
    state = state.copyWith(
      radioStation: null,
      radioTitle: null,
      radioArtwork: null,
      radioSeekable: false,
      radioBehindLive: Duration.zero,
      radioWindow: Duration.zero,
    );
  }

  /// Jump back to the live edge. Reconnecting is the one move that works on every
  /// stream (seekable or not), so we reopen rather than seek.
  Future<void> radioGoLive() async {
    final s = state.radioStation;
    if (s == null) return;
    _radioEdge = Duration.zero;
    _radioTickWall = null;
    state = state.copyWith(radioBehindLive: Duration.zero);
    await _player.open(Media(s.url));
  }

  /// Rewind/skip within the buffered window (seekable streams only). Negative to
  /// rewind. Clamped to the window and the live edge.
  Future<void> radioSeekBy(Duration delta) async {
    if (!state.isRadio || !state.radioSeekable) return;
    final pos = _player.state.position;
    final lowest = _radioEdge - state.radioWindow;
    var target = pos + delta;
    if (target < lowest) target = lowest;
    if (target > _radioEdge) target = _radioEdge;
    if (target < Duration.zero) target = Duration.zero;
    await _player.seek(target);
  }

  /// Seek to a point [behind] the live edge (0 = live), for the scrub bar.
  Future<void> radioSeekBehind(Duration behind) async {
    if (!state.isRadio || !state.radioSeekable) return;
    var target = _radioEdge - behind;
    if (target < Duration.zero) target = Duration.zero;
    await _player.seek(target);
  }

  void _startRadioTick() {
    _radioTick?.cancel();
    _radioTick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!state.isRadio) return;
      final now = DateTime.now();
      final last = _radioTickWall ?? now;
      _radioTickWall = now;
      // The live edge advances in real time regardless of what we're doing.
      _radioEdge += now.difference(last);
      final pos = _player.state.position;
      // Snap the edge to playback while we're at (or ahead of) it, so normal
      // live playback stays at 0 behind and small clock drift can't accumulate.
      if (_player.state.playing && pos >= _radioEdge - const Duration(seconds: 1)) {
        _radioEdge = pos > _radioEdge ? pos : _radioEdge;
        if ((_radioEdge - pos) < const Duration(seconds: 1)) _radioEdge = pos;
      }
      var behind = _radioEdge - pos;
      if (behind < Duration.zero) behind = Duration.zero;
      final window = _radioEdge < _radioMaxWindow ? _radioEdge : _radioMaxWindow;
      bool seekable = state.radioSeekable;
      try {
        final sk = await (_player.platform as dynamic).getProperty('seekable');
        seekable = sk == 'yes' || sk == '1' || sk == true;
      } catch (_) {}
      // Only push when something the UI shows actually changed (avoid rebuild
      // spam): behind to the second, seekable, or window to the second.
      final changed = seekable != state.radioSeekable ||
          behind.inSeconds != state.radioBehindLive.inSeconds ||
          window.inSeconds != state.radioWindow.inSeconds;
      if (changed) {
        state = state.copyWith(
          radioSeekable: seekable,
          radioBehindLive: behind,
          radioWindow: window,
        );
      }
    });
  }

  void _startIcyPolling() {
    _radioIcyTimer?.cancel();
    Future<void> poll() async {
      if (!state.isRadio) return;
      try {
        final t = await (_player.platform as dynamic)
            .getProperty('metadata/by-key/icy-title');
        final raw = (t is String) ? t : '';
        final title = _sanitizeIcy(raw);
        // Per-song album art if the station embeds it (iHeart amgArtworkURL).
        final embedded = _extractArtwork(raw);
        if (title.isEmpty) {
          // Ad break or metadata with no track: drop to the station's live
          // label + logo instead of holding a stale song.
          _artLookupKey = null;
          if (state.radioTitle != null || state.radioArtwork != null) {
            state = state.copyWith(radioTitle: null, radioArtwork: null);
            final s = state.radioStation;
            if (s != null) _pushRadioNowPlaying(s, null);
          }
          return;
        }
        final titleChanged = title != state.radioTitle;
        if (titleChanged) {
          // New song: adopt embedded art if present, else clear the old art and
          // look it up generically (iTunes) so any station gets cover art.
          state = state.copyWith(
            radioTitle: title,
            radioArtwork: embedded.isNotEmpty ? embedded : null,
          );
          final s = state.radioStation;
          if (s != null) _pushRadioNowPlaying(s, title);
          if (embedded.isEmpty) {
            _artLookupKey = null;
            unawaited(_resolveArtwork(title));
          } else {
            _artLookupKey = title.toLowerCase();
          }
        } else if (embedded.isNotEmpty && embedded != state.radioArtwork) {
          state = state.copyWith(radioArtwork: embedded);
          final s = state.radioStation;
          if (s != null) _pushRadioNowPlaying(s, state.radioTitle);
        }
      } catch (_) {}
    }

    poll();
    _radioIcyTimer =
        Timer.periodic(const Duration(seconds: 6), (_) => poll());
  }

  /// Clean up an ICY "now playing" line. Many stations (iHeart, etc.) send a
  /// structured StreamTitle with embedded key="value" fields plus a lot of junk
  /// (`title="X",artist="Y",url="song_spot=...MediaBaseId=..."`); pull the real
  /// title/artist out and format "Artist - Title". Plain "Artist - Title"
  /// strings pass through untouched.
  static String _sanitizeIcy(String raw) {
    final t = raw.replaceAll('\u0000', '').trim();
    if (t.isEmpty) return '';
    var s = _icyDecodeEntities(t);

    // Unwrap a `StreamTitle='...'` / `StreamTitle="..."` wrapper if a feed sends
    // the whole assignment rather than just the value.
    final wrap = RegExp(r'''^StreamTitle\s*=\s*['"](.*)['"];?\s*$''',
            caseSensitive: false, dotAll: true)
        .firstMatch(s);
    if (wrap != null) s = wrap.group(1)!.trim();

    // Strip a leading "Now Playing:" / "Now playing -" label.
    s = s.replaceFirst(
        RegExp(r'^\s*now\s*playing\s*[:\-–—]\s*', caseSensitive: false), '');
    if (s.isEmpty) return '';

    // 1) RDS asterisk: `Song*<title>*<artist>*…` (Spot/Ad/Promo = ad → drop).
    final star = RegExp(
            r'^(Song|Spot|Track|Music|News|Promo|Ad|Advert)\s*\*\s*([^*]*?)\s*\*\s*([^*]*?)\s*(?:\*|$)',
            caseSensitive: false)
        .firstMatch(s);
    if (star != null) {
      final type = star.group(1)!.toLowerCase();
      if (const {'spot', 'ad', 'promo', 'advert'}.contains(type)) return '';
      return _icyFinish(_icyJoin(star.group(3), star.group(2)));
    }

    // 2) JSON now-playing blob: {"artist":"X","title":"Y"} / {"song":…}.
    if (s.contains('{') && s.contains('"')) {
      final r = _icyJoin(
        _icyJson(s, const ['artist', 'performer', 'author', 'albumartist']),
        _icyJson(s, const ['title', 'song', 'track', 'songtitle', 'name']),
      );
      if (r.isNotEmpty) return _icyFinish(r);
    }
    // 3) iHeart `text="Song"` with the artist before it, e.g.
    //    `Doja Cat - text="Paint The Town Red" song_spot="M" MediaBaseId=…`.
    final iheart =
        RegExp(r'^(.*?)\s*\btext\s*=\s*"([^"]+)"', caseSensitive: false)
            .firstMatch(s);
    if (iheart != null) {
      final prefix =
          iheart.group(1)!.replaceAll(RegExp(r'[\s\-–—]+$'), '').trim();
      return _icyFinish(_icyJoin(prefix, iheart.group(2)));
    }

    // 4) Explicit key=value fields (quoted or unquoted; , ; & | newline
    //    separated): `title="X",artist="Y"`, `artist=X; song=Y`, …
    final kt = _icyKv(s, const ['title', 'song', 'track', 'songtitle']);
    final ka = _icyKv(s, const ['artist', 'performer', 'author', 'albumartist']);
    if ((kt != null && kt.isNotEmpty) || (ka != null && ka.isNotEmpty)) {
      return _icyFinish(_icyJoin(ka, kt));
    }

    // 5) A bare `key="..."` blob with no readable prefix — metadata with no song
    //    (iHeart ad break `adContext="<base64 VAST url>"`) → show nothing.
    if (RegExp(r'^\w+\s*=\s*"').hasMatch(s)) return '';

    // 6) Drop a trailing "key=…" junk tail, keeping the clean "Artist - Title"
    //    prefix (`Artist - Title song_spot="F" MediaBaseId=1234` → `Artist - Title`).
    final cut = s.indexOf(RegExp(r'\s+\w+\s*=\s*["\d]'));
    if (cut > 0) s = s.substring(0, cut).trim();

    // 7) Plain string (Artist - Title, or a single field).
    return _icyFinish(s);
  }

  /// Join an (artist, title) pair as "Artist - Title", dropping either side when
  /// it's blank so there's never a dangling separator.
  static String _icyJoin(String? artist, String? title) =>
      [artist?.trim() ?? '', title?.trim() ?? '']
          .where((x) => x.isNotEmpty)
          .join(' - ');

  /// Decode the handful of HTML entities feeds commonly emit.
  static String _icyDecodeEntities(String s) => s
      .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
      .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
      .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
      .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
      .replaceAll(RegExp(r'&apos;', caseSensitive: false), "'")
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));

  /// First non-empty JSON string field among [keys], e.g. `"title":"X"`.
  static String? _icyJson(String s, List<String> keys) {
    for (final k in keys) {
      final m = RegExp('"$k"' r'\s*:\s*"([^"]*)"', caseSensitive: false)
          .firstMatch(s);
      final v = m?.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// First non-empty `key=value` among [keys], quoted or unquoted.
  static String? _icyKv(String s, List<String> keys) {
    for (final k in keys) {
      final q = RegExp('\\b$k' r'''\s*=\s*(?:"([^"]*)"|'([^']*)')''',
              caseSensitive: false)
          .firstMatch(s);
      if (q != null) {
        final v = (q.group(1) ?? q.group(2) ?? '').trim();
        if (v.isNotEmpty) return v;
      }
      final u = RegExp('\\b$k' r'\s*=\s*(.+?)(?=\s+\w+\s*=|[,;&|]|$)',
              caseSensitive: false)
          .firstMatch(s);
      final uv = u?.group(1)?.trim();
      if (uv != null && uv.isNotEmpty && !RegExp(r'^\w+\s*=').hasMatch(uv)) {
        return uv;
      }
    }
    return null;
  }

  /// Normalize dashes/whitespace, strip a dangling separator, drop ad markers,
  /// and cap the length.
  static String _icyFinish(String input) {
    final s = input
        .replaceAll(RegExp(r'[‐‑‒–—―−]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s*-\s*$'), '')
        .replaceAll(RegExp(r'^\s*-\s*'), '')
        .trim();
    if (s.isEmpty || _icyAdMarkers.contains(s.toLowerCase())) return '';
    return s.length > 200 ? s.substring(0, 200).trim() : s;
  }

  /// Ad/placeholder StreamTitles meaning "no song is playing".
  static const _icyAdMarkers = {
    'advertisement', 'commercial break', 'commercial', 'ad break', 'ads',
    'advert', 'intermission', 'station id', 'unknown', 'no program',
    'offline', 'no title', 'n/a', 'na', 'loading', 'buffering',
    'live stream', 'live', 'radio', 'music', 'default'
  };

  /// Pull a per-song artwork URL out of the raw StreamTitle when the station
  /// embeds one. iHeart streams carry `amgArtworkURL="..."`; most don't, in
  /// which case we fall back to a generic lookup ([_resolveArtwork]).
  static String _extractArtwork(String raw) {
    final m = RegExp(r'amgArtworkURL\s*=\s*"([^"]+)"', caseSensitive: false)
        .firstMatch(raw);
    return m?.group(1)?.trim() ?? '';
  }

  /// Generic album-art lookup for any station that reports a clean
  /// "Artist - Title": queries the free iTunes Search API and, if the song is
  /// still current, sets it as the radio artwork. Best-effort; silent on miss.
  Future<void> _resolveArtwork(String title) async {
    final key = title.toLowerCase();
    _artLookupKey = key;
    try {
      final dio = await secureDio(
          options: BaseOptions(connectTimeout: const Duration(seconds: 6)));
      // Normalize the term: collabs come through as "A / B - Title" or
      // "A & B - Title", which iTunes matches poorly with the separators intact.
      final term = title
          .replaceAll(RegExp(r'\s*[/,&]\s*'), ' ')
          .replaceAll(RegExp(r'\s+[-–—]\s+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final res = await dio.get(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': term.isEmpty ? title : term,
          'media': 'music',
          'entity': 'song',
          'limit': 1,
        },
        options: Options(
            headers: {'User-Agent': 'Fathom'}, responseType: ResponseType.plain),
      );
      // The song may have changed (or radio stopped) while we were fetching.
      if (_artLookupKey != key || !state.isRadio) return;
      final body = res.data;
      final decoded = body is String ? jsonDecode(body) : body;
      final results = (decoded is Map) ? decoded['results'] as List? : null;
      if (results == null || results.isEmpty) return;
      final art100 = (results.first as Map)['artworkUrl100'] as String?;
      if (art100 == null || art100.isEmpty) return;
      // iTunes serves 100px; bump the size token for a crisp cover.
      final big = art100.replaceAll('100x100bb', '600x600bb');
      if (_artLookupKey == key && state.isRadio && state.radioTitle == title) {
        state = state.copyWith(radioArtwork: big);
        final s = state.radioStation;
        if (s != null) _pushRadioNowPlaying(s, title);
      }
    } catch (_) {}
  }

  /// Called when a resolved artwork URL fails to load, so the UI falls back to
  /// the station logo cleanly (and the redundant logo chip disappears).
  void clearRadioArtwork(String url) {
    if (state.isRadio && state.radioArtwork == url) {
      _artLookupKey = null;
      state = state.copyWith(radioArtwork: null);
    }
  }

  void _pushRadioNowPlaying(RadioStation s, String? icy) {
    final h = _handler;
    if (h == null) return;
    final hasIcy = icy != null && icy.isNotEmpty;
    final art = (state.radioArtwork != null && state.radioArtwork!.isNotEmpty)
        ? state.radioArtwork!
        : (s.favicon ?? '');
    h.setNowPlaying(MediaItem(
      id: s.id,
      title: hasIcy ? icy : s.name,
      artist: hasIcy ? s.name : (s.tags ?? 'Radio'),
      artUri: art.isNotEmpty ? Uri.tryParse(art) : null,
    ));
  }

  void _reportStart(String itemId) {
    final c = _ctx();
    if (c == null) return;
    _reportedId = itemId;
    unawaited(c.client.reportPlaybackStart(
      baseUrl: c.session.baseUrl,
      token: c.session.accessToken,
      itemId: itemId,
      positionTicks: 0,
    ));
  }

  void _reportProgress() {
    final c = _ctx();
    final id = _reportedId;
    if (c == null || id == null) return;
    unawaited(c.client.reportPlaybackProgress(
      baseUrl: c.session.baseUrl,
      token: c.session.accessToken,
      itemId: id,
      positionTicks: _lastPositionTicks,
    ));
  }

  void _reportStopped() {
    final c = _ctx();
    final id = _reportedId;
    if (c == null || id == null) return;
    unawaited(c.client.reportPlaybackStopped(
      baseUrl: c.session.baseUrl,
      token: c.session.accessToken,
      itemId: id,
      positionTicks: _lastPositionTicks,
    ));
    _reportedId = null;
  }

  Future<void> togglePlay() {
    // While casting, drive the cast device, not local playback (otherwise
    // hitting play resumes audio on the phone alongside the cast).
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      final c = ref.read(castControllerProvider.notifier);
      return cast.playing ? c.pause() : c.play();
    }
    return _player.playOrPause();
  }

  /// Hand playback back to the local player when a cast session ends: jump to
  /// the track the receiver was on, seek to its position, and resume if it was
  /// playing. The local playlist mirrors the cast queue, so indices line up.
  Future<void> _resumeLocalFromCast(
      String? url, int positionMs, bool wasPlaying) async {
    if (url != null) {
      final id = RegExp(r'/Audio/([0-9a-fA-F]+)/').firstMatch(url)?.group(1);
      if (id != null) {
        final idx = state.queue.indexWhere((t) => t.id == id);
        if (idx >= 0) await _player.jump(idx);
      }
    }
    if (positionMs > 0) {
      await _player.seek(Duration(milliseconds: positionMs));
    }
    if (wasPlaying) {
      await _player.play();
    } else {
      await _player.pause();
    }
  }

  Future<void> next() {
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      return ref.read(castControllerProvider.notifier).queueNext();
    }
    return _player.next();
  }

  Future<void> previous() {
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      return ref.read(castControllerProvider.notifier).queuePrev();
    }
    return _player.previous();
  }

  Future<void> seek(Duration position) {
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      return ref
          .read(castControllerProvider.notifier)
          .seek(position.inMilliseconds);
    }
    return _player.seek(position);
  }

  /// Index of the now-playing track within the visible queue.
  int get currentIndex {
    final id = state.current?.id;
    if (id == null) return -1;
    return state.queue.indexWhere((t) => t.id == id);
  }

  /// Jump straight to a queue entry (indexes match the player's order).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _player.jump(index);
  }

  /// Drop a track from the queue.
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _player.remove(index);
  }

  /// Reorder the queue. media_kit's move(from, to) makes [from] take the place
  /// of the entry at [to] (mpv semantics), which matches ReorderableListView's
  /// raw newIndex without the usual decrement. The playlist stream then
  /// re-syncs the visible order.
  Future<void> moveQueue(int oldIndex, int newIndex) async {
    final len = state.queue.length;
    if (oldIndex < 0 || oldIndex >= len) return;
    // Allow to == len so a track can be dropped in the last slot (media_kit
    // treats that as insert-at-end); only clamp genuinely out-of-range values.
    final to = newIndex < 0 ? 0 : (newIndex > len ? len : newIndex);
    if (to == oldIndex) return;
    await _player.move(oldIndex, to);
  }

  /// Append a track to the end of the queue, or start fresh if nothing plays.
  Future<void> addToQueue(BaseItemDto track) async {
    if (!state.hasTrack) {
      await playQueue([track], 0);
      return;
    }
    final c = _ctx();
    if (c == null) return;
    _byId[track.id] = track;
    await _player.add(Media(c.client.audioStreamUrl(
      baseUrl: c.session.baseUrl,
      itemId: track.id,
      token: c.session.accessToken,
    )));
  }

  /// Queue a track to play right after the current one.
  Future<void> playNext(BaseItemDto track) async {
    if (!state.hasTrack) {
      await playQueue([track], 0);
      return;
    }
    final c = _ctx();
    if (c == null) return;
    _byId[track.id] = track;
    // Capture positions before the add so a concurrent playlist event can't
    // shift them: the appended track lands at the old length.
    final insertIndex = state.queue.length;
    final target = currentIndex + 1;
    await _player.add(Media(c.client.audioStreamUrl(
      baseUrl: c.session.baseUrl,
      itemId: track.id,
      token: c.session.accessToken,
    )));
    if (target < insertIndex) await _player.move(insertIndex, target);
  }

  Future<void> toggleShuffle() async {
    final value = !state.shuffle;
    await _player.setShuffle(value);
    state = state.copyWith(shuffle: value);
  }

  Future<void> cycleRepeat() async {
    final next = switch (state.repeat) {
      PlaylistMode.none => PlaylistMode.loop,
      PlaylistMode.loop => PlaylistMode.single,
      PlaylistMode.single => PlaylistMode.none,
    };
    await _player.setPlaylistMode(next);
    state = state.copyWith(repeat: next);
  }
}

final audioControllerProvider =
    NotifierProvider<AudioController, AudioState>(AudioController.new);

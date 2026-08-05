import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/youtube_streams.dart';
import '../routing/route_observer.dart';
import '../state/audio_player.dart';
import '../state/media_session.dart';
import '../state/pip_controller.dart';
import '../state/preferences.dart';
import '../state/youtube_providers.dart';
import '../state/volume_sync.dart';
import '../widgets/player_controls.dart';
import '../services/live_players.dart';
import '../services/sponsorblock.dart';
import '../services/tv_mode.dart';
import '../models/youtube_caption.dart';
import '../models/youtube_chapter.dart';

/// Plays a YouTube video (or any direct URL) with the shared Fathom controls.
///
/// This is a bare player with no Scaffold, so it works both full-screen (see
/// [YoutubePlayerScreen], used for trailers) and embedded in the watch page.
/// A way to drive the player from the page around it.
///
/// The player owns its mpv instance, and its State is private, so a description
/// timestamp or a chapter link needs some handle to seek with. Kept to the one
/// verb that's actually needed rather than exposing the Player itself.
class YoutubePlayerHandle {
  Future<void> Function(Duration)? _seek;

  bool get isReady => _seek != null;

  Future<void> seek(Duration position) async => _seek?.call(position);
}

class YoutubeVideoPlayer extends ConsumerStatefulWidget {
  final String url;
  final String? title;

  /// Trailers use the Trailer Quality preference and get a "Trailer" suffix;
  /// the YouTube section uses the YouTube Quality preference.
  final bool isTrailer;

  /// Overrides the back button; defaults to popping the route.
  final VoidCallback? onBack;

  /// Fires when playback reaches the end (used for autoplay-next).
  final VoidCallback? onEnded;

  /// Embedded players keep their controls up and drop the title bar, since the
  /// surrounding page already shows the title and the pointer spends most of
  /// its time off the video.
  final bool embedded;

  /// Where to pick up from, if this video was partly watched before. A future
  /// because history is read from storage, so it usually isn't ready when the
  /// player is first built.
  final Future<Duration?>? resumeAt;

  /// Reports playback progress so the caller can store history. Fires
  /// periodically and on dispose.
  final void Function(Duration position, Duration duration)? onProgress;

  /// Chapters, when the caller knows them. The watch page does; the trailer
  /// player doesn't, and passes none.
  final List<YoutubeChapter> chapters;

  /// Lets the surrounding page seek, e.g. from a description timestamp.
  final YoutubePlayerHandle? handle;

  /// From the YouTube settings. The Jellyfin player keeps the shared default.
  final int seekBackSeconds;
  final int seekForwardSeconds;

  /// Toggles the watch page's theater mode. Null hides the control-bar button.
  final VoidCallback? onToggleTheater;

  /// Whether theater mode is currently on (for the button's active state).
  final bool theaterActive;

  /// Advances to the next video (queue, else autoplay). Powers the Next button;
  /// null hides it (trailers, standalone).
  final VoidCallback? onNext;

  /// Channel name and thumbnail URL for the OS media session (desktop tray/media
  /// keys). Optional; trailers pass neither.
  final String? channel;
  final String? artUrl;

  const YoutubeVideoPlayer({
    super.key,
    required this.url,
    this.title,
    this.isTrailer = false,
    this.onBack,
    this.onEnded,
    this.embedded = false,
    this.chapters = const [],
    this.handle,
    this.seekBackSeconds = 10,
    this.seekForwardSeconds = 30,
    this.resumeAt,
    this.onProgress,
    this.onToggleTheater,
    this.theaterActive = false,
    this.onNext,
    this.channel,
    this.artUrl,
  });

  @override
  ConsumerState<YoutubeVideoPlayer> createState() => _YoutubeVideoPlayerState();
}

class _YoutubeVideoPlayerState extends ConsumerState<YoutubeVideoPlayer>
    with RouteAware {
  late final Player _player;
  late final VideoController _controller;
  // True when this screen took over a still-playing player from the mini dock
  // (the video was minimized and is now being reopened), rather than creating a
  // fresh one. Reclaiming skips the reload and keeps playback seamless.
  late final bool _reclaimed;
  late final VolumeSync _volume = VolumeSync(
    player: _player,
    read: () => ref.read(preferencesProvider).asData?.value.volume ?? 100,
    write: (v) => ref
        .read(preferencesProvider.notifier)
        .edit((x) => x.copyWith(volume: v)),
  );
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  // OS media session (desktop tray / media keys), same mechanism as the Jellyfin
  // video player. Captured so dispose() can release it without touching ref.
  StreamSubscription<Duration>? _mediaPosSub;
  VideoMediaSessionController? _mediaSession;
  final Object _mediaToken = Object();
  int _mediaLastPosSec = -1;
  bool _ready = false;
  String? _error;
  double _preMuteVolume = 100;

  YtStreams _streams = const YtStreams();
  List<YtQuality> _qualities = const [];
  String _qualityLabel = 'Auto';
  // Stats-overlay open state, shared with the fullscreen route (a new controls
  // instance) so toggling fullscreen keeps it open.
  final ValueNotifier<bool> _statsOpen = ValueNotifier<bool>(false);
  List<YoutubeCaption> _captions = const [];
  YoutubeCaption? _caption; // null = subtitles off

  List<SponsorSegment> _sponsors = const [];
  StreamSubscription<Duration>? _sponsorSub;
  /// Skipped once each: re-skipping fights the viewer who seeks back in.
  final Set<String> _skipped = {};
  String? _audioUrl; // set in adaptive mode
  bool _isLive = false; // muxedUrl is a live HLS/DASH manifest
  StreamSubscription<int?>? _firstFrameSub;
  // PERF DIAGNOSTIC (temporary): mpv verbose log + throttle probe, to pinpoint
  // the video-startup cost. Flip _perfDiag off to silence it.
  static const bool _perfDiag = false;
  StreamSubscription<PlayerLog>? _mpvLogSub;
  String? _probeUrl;
  int _probeBitrate = 0;
  bool _fellBack = false;
  Timer? _fallbackTimer;
  Timer? _progressTimer;
  bool _resumed = false;
  // Set when the player is handed to the floating mini player: dispose() must
  // then leave the mpv instance alone (the PiP dock owns it now).
  bool _minimized = false;
  // Armed in deactivate(), cleared in activate(): tells a deferred pause whether
  // the widget really left the tree or was just reparented by its GlobalKey.
  bool _deactivating = false;

  String get _qualityPref {
    // A stalled/failed load can resume after the screen is gone; touching `ref`
    // then throws. Default to auto rather than read a dead provider.
    if (!mounted) return 'auto';
    final p = ref.read(preferencesProvider).asData?.value;
    if (p == null) return 'auto';
    return widget.isTrailer ? p.trailerQuality : p.youtubeQuality;
  }

  /// The initial rendition for the current preference: 'auto' is a
  /// bandwidth-aware pick (up to 1080p), an explicit height picks the best at or
  /// below it.
  Future<YtQuality?> _preferredQuality() async {
    if (_qualityPref == 'auto') return _autoQuality();
    return defaultQualityFor(_qualities, _qualityPref);
  }

  /// Bandwidth-aware "Auto" pick, probing the audio stream to size the choice.
  Future<YtQuality?> _autoQuality() {
    final probe =
        _audioUrl ?? (_qualities.isNotEmpty ? _qualities.first.url : '');
    return autoQualityByBandwidth(_qualities, probe);
  }

  @override
  void initState() {
    super.initState();
    // Reopening a minimized video: take back its live player from the dock so
    // playback never restarts. The dock's player/controller are plain fields we
    // can read here, but every state change is deferred to a post-frame
    // callback: mutating a provider during initState throws and aborts the
    // build (which blanks the screen and crashes mpv on the way out).
    final pipNotifier = ref.read(pipProvider.notifier);
    final dockedPlayer = pipNotifier.player;
    final dockedController = pipNotifier.controller;
    final reclaimId = widget.embedded ? youtubeVideoId(widget.url) : null;
    final canReclaim = reclaimId != null &&
        dockedPlayer != null &&
        dockedController != null &&
        ref.read(pipProvider).matchId == reclaimId;
    if (canReclaim) {
      _player = dockedPlayer;
      _controller = dockedController;
      _reclaimed = true;
      // Release the dock's ownership after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        pipNotifier.detachForReclaim();
      });
    } else {
      _player = _perfDiag
          ? Player(
              configuration:
                  const PlayerConfiguration(logLevel: MPVLogLevel.v))
          : Player();
      _controller = VideoController(_player);
      _reclaimed = false;
      if (_perfDiag) {
        _mpvLogSub = _player.stream.log.listen((e) {
          final t = e.text.trim();
          if (t.isEmpty) return;
          const keys = [
            'hls', 'http', 'tcp', 'tls', 'stream', 'cache', 'demux', 'ffmpeg',
            'segment', 'reconnect', 'timeout', 'eof', 'network', 'open',
            'audio', 'probe', 'analyze', 'lavf', 'vd/', 'ad/', 'decoder',
            'buffer'
          ];
          final l = t.toLowerCase();
          if (keys.any(l.contains)) {
            debugPrint('[mpv:${e.prefix}/${e.level}] $t');
          }
        });
      }
      // A different video (or none) may be docked; silence it after this frame.
      if (widget.embedded && dockedPlayer != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          pipNotifier.close();
        });
      }
    }
    // Volume is shared and remembered across every player.
    _volume.attach();
    widget.handle?._seek = _player.seek;
    // Quitting outright skips dispose(); the registry tears mpv down
    // before the engine goes. A reclaimed player is already registered.
    if (!_reclaimed) LivePlayers.add(_player);
    _playingSub = _player.stream.playing.listen((playing) {
      _mediaSession?.updatePlayback(playing: playing, token: _mediaToken);
      if (playing) {
        // Playback started, so the adaptive path is fine: cancel the fallback.
        _fallbackTimer?.cancel();
        if (!_ready && mounted) setState(() => _ready = true);
      }
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) widget.onEnded?.call();
    });
    if (widget.onProgress != null) {
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        // The timer outlives deactivation; don't report from a dead widget.
        if (mounted) _reportProgress();
      });
    }
    // OS media session: keep its scrubber roughly live (throttled to 1s).
    _mediaSession = ref.read(videoMediaSessionProvider.notifier);
    _mediaPosSub = _player.stream.position.listen((p) {
      if (p.inSeconds != _mediaLastPosSec) {
        _mediaLastPosSec = p.inSeconds;
        _mediaSession?.updatePlayback(position: p, token: _mediaToken);
      }
    });
    // Register after the first frame (mutating a provider in initState throws).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _beginMediaSession();
    });
    _load();
  }

  void _beginMediaSession() {
    final ms = _mediaSession;
    if (ms == null) return;
    ms.begin(
      VideoMediaSession(
        title: widget.title ?? 'YouTube',
        subtitle: widget.channel,
        artUrl: widget.artUrl,
        playing: _player.state.playing,
        position: _player.state.position,
        duration: _player.state.duration,
        canNext: widget.onNext != null,
        canPrev: false,
        onPlay: _player.play,
        onPause: _player.pause,
        onStop: _player.pause,
        onNext: widget.onNext != null ? () async => widget.onNext!() : null,
        onSeek: (d) async => _player.seek(d),
      ),
      _mediaToken,
    );
  }

  @override
  void didUpdateWidget(YoutubeVideoPlayer old) {
    super.didUpdateWidget(old);
    // Details (title, channel, and whether there's a next) load after the first
    // frame, so re-register when any of them change — otherwise the tray keeps
    // the initial state and never gets a Next button once autoplay/queue kick in.
    if (widget.title != old.title ||
        widget.channel != old.channel ||
        widget.artUrl != old.artUrl ||
        (widget.onNext == null) != (old.onNext == null)) {
      // Deferred: begin() mutates a provider, which isn't allowed during
      // didUpdateWidget (the build phase).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _beginMediaSession();
      });
    }
  }

  void _reportProgress() {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (pos <= Duration.zero || dur <= Duration.zero) return;
    // Never let a reporting failure escape: this runs from a timer and from
    // dispose(), and an exception there would abort teardown and strand the
    // player (still playing).
    try {
      widget.onProgress?.call(pos, dur);
    } catch (_) {}
  }

  /// Seeks to the resume point once the demuxer knows the duration, so an early
  /// seek isn't dropped. Only ever runs once per video.
  Future<void> _maybeResume() async {
    if (_resumed || widget.resumeAt == null) return;
    _resumed = true;
    final at = await widget.resumeAt;
    if (at == null || at <= Duration.zero || !mounted) return;
    try {
      if (_player.state.duration <= at) {
        await _player.stream.duration
            .firstWhere((d) => d > at)
            .timeout(const Duration(seconds: 10));
      }
      await _player.seek(at);
    } catch (_) {
      // Duration never arrived; just leave it at the start.
    }
  }

  Future<void> _load() async {
    // Starting a video: pause the app-wide music/radio player so we don't hear
    // both at once (Jellyfin video does the same). Reading the provider and
    // calling pause is safe here — _load runs from initState but this is a
    // method call, not a provider mutation.
    final audio = ref.read(audioPlayerProvider);
    if (audio.state.playing) unawaited(audio.pause());
    // Reclaimed from the dock: the stream is already open and playing. Don't
    // reopen it (that would restart the video); just repopulate the menus
    // (quality, subtitles, chapters) and sponsor-skip that the old screen held.
    if (_reclaimed) {
      // _load() runs synchronously from initState up to the first await, so set
      // the field directly here rather than via setState (illegal pre-build).
      _ready = true;
      unawaited(_refreshMetadata());
      return;
    }
    final sw = Stopwatch()..start();
    // Resolve the failure message now, while the context is definitely valid: a
    // load can fail after the screen is deactivated, and looking it up then is
    // unsafe.
    final loadFailedMsg = AppLocalizations.of(context).playerYoutubeLoadFailed;
    try {
      if (!isYoutubeUrl(widget.url)) {
        await _player.open(Media(widget.url));
        return;
      }
      final s = await resolveYoutubeStreams(widget.url);
      debugPrint('[yt] streams ready at ${sw.elapsedMilliseconds}ms');
      if (!mounted) return;
      _streams = s;
      _isLive = s.isLive;
      // Keep the network cache in RAM rather than media_kit's default of
      // writing it to disk, and give slow segments a real timeout. (These are
      // safe; they don't fix the media_kit-vs-raw-mpv live start-up gap, which
      // is inside media_kit's own stream layer.)
      try {
        final mpv = _player.platform as dynamic;
        await mpv.setProperty('cache-on-disk', 'no');
        await mpv.setProperty('network-timeout', '30');
      } catch (_) {}
      // One-shot: log when the first video frame actually lands, so start-up
      // cost is visible end to end (resolution + mpv buffering to first frame).
      _firstFrameSub = _player.stream.width.listen((w) {
        if (w != null && w > 0) {
          debugPrint('[yt] first frame at ${sw.elapsedMilliseconds}ms');
          _firstFrameSub?.cancel();
          _firstFrameSub = null;
          // Now measure the chosen video URL's raw throughput vs its bitrate:
          // a ratio near 1x means googlevideo is throttling us to ~realtime
          // (which would be the buffering cost); a high ratio rules that out.
          if (_perfDiag && _probeUrl != null) {
            unawaited(_probeThrottle(_probeUrl!, _probeBitrate, sw));
          }
        }
      });
      // Fire-and-forget: these are extras, and waiting on them would delay the
      // first frame of every video.
      unawaited(_loadCaptions());
      unawaited(_loadSponsors());
      if (s.isAdaptive) {
        _audioUrl = s.audioUrl;
        _qualities = s.qualities;
        final def = await _preferredQuality();
        _qualityLabel = _qualityPref == 'auto' ? 'Auto' : (def?.label ?? 'Auto');
        _probeUrl = def?.url;
        _probeBitrate = def?.bitrate ?? 0;
        if (def != null) await _playAdaptive(def, sw);
        debugPrint('[yt] player opened (adaptive) at ${sw.elapsedMilliseconds}ms');
        _armFallback();
        await _maybeResume();
        return;
      }
      _qualities = s.muxedQualities;
      await _player.open(Media(s.muxedUrl ?? widget.url));
      debugPrint('[yt] player opened (muxed/live) at ${sw.elapsedMilliseconds}ms');
      // Live has no meaningful resume point; VOD restores the saved position.
      if (!s.isLive) await _maybeResume();
    } catch (e, st) {
      debugPrint('[yt] load failed for ${widget.url}: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() => _error = loadFailedMsg);
      }
    }
  }

  /// Repopulate the track/quality lists and sponsor segments for a reclaimed
  /// player without touching playback. The stream URLs resolve to the same
  /// video that's already open, so this only refills the menus.
  Future<void> _refreshMetadata() async {
    try {
      if (!isYoutubeUrl(widget.url)) return;
      final s = await resolveYoutubeStreams(widget.url);
      if (!mounted) return;
      _streams = s;
      unawaited(_loadCaptions());
      unawaited(_loadSponsors());
      if (s.isAdaptive) {
        _audioUrl = s.audioUrl;
        setState(() {
          _qualities = s.qualities;
          // The docked player's exact rendition isn't known; label it Auto
          // until the viewer picks one.
          _qualityLabel =
              defaultQualityFor(s.qualities, _qualityPref)?.label ?? 'Auto';
        });
      } else {
        setState(() => _qualities = s.muxedQualities);
      }
    } catch (_) {
      // Menus stay minimal; playback is unaffected.
    }
  }

  Future<void> _loadCaptions() async {
    final id = youtubeVideoId(widget.url);
    if (id == null) return;
    final caps = await resolveYoutubeCaptions(id);
    if (!mounted || caps.isEmpty) return;
    setState(() => _captions = caps);
  }

  Future<void> _loadSponsors() async {
    final id = youtubeVideoId(widget.url);
    if (id == null || !mounted) return;
    final segments =
        await ref.read(youtubeSponsorSegmentsProvider(id).future);
    if (!mounted || segments.isEmpty) return;
    setState(() => _sponsors = segments);

    _sponsorSub?.cancel();
    _sponsorSub = _player.stream.position.listen(_maybeSkipSponsor);
  }

  /// Jumps past a sponsor segment the playhead has entered.
  void _maybeSkipSponsor(Duration position) {
    for (final s in _sponsors) {
      if (_skipped.contains(s.uuid) || !s.contains(position)) continue;
      // Marked before seeking: the seek fires more positions, and without this
      // a slow seek can trigger the same skip twice.
      _skipped.add(s.uuid);
      unawaited(_player.seek(s.end));

      final notify = ref.read(preferencesProvider).asData?.value
              .youtubeSponsorBlockNotify ??
          true;
      // Silently jumping the video is indistinguishable from a bug or a bad
      // seek, so by default it says what it did and offers a way back.
      if (notify && mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          // Only one at a time: back-to-back segments would otherwise queue,
          // and each waits its full turn before the next appears.
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 4),
            // Load-bearing. Flutter defaults persist to `action != null`
            // (snack_bar.dart: `persist = persist ?? action != null`), so
            // adding Undo silently opted this into never going away — it sat
            // there until the action or the route was dismissed. The offer to
            // undo shouldn't outlive the moment it's useful.
            persist: false,
            content: Text(l.playerSkippedSegment(
                s.category.label.toLowerCase(), s.length.inSeconds)),
            action: SnackBarAction(
              label: l.playerUndo,
              onPressed: () => unawaited(_player.seek(s.start)),
            ),
          ));
      }
      return;
    }
  }

  /// mpv loads the track from its URL, the same mechanism as the external audio
  /// track in adaptive mode. Passing null clears it.
  Future<void> _setCaption(YoutubeCaption? c) async {
    setState(() => _caption = c);
    try {
      await _player.setSubtitleTrack(
        c == null
            ? SubtitleTrack.no()
            : SubtitleTrack.uri(c.vttUrl, title: c.label, language: c.code),
      );
    } catch (_) {
      if (mounted) setState(() => _caption = null);
    }
  }

  Future<void> _showChapterMenu() async {
    await _sheet<YoutubeChapter>(
      title: AppLocalizations.of(context).playerChapters,
      options: widget.chapters,
      isSelected: (c) => c == _currentChapter,
      label: (c) => '${c.startLabel}   ${c.title}',
      onSelect: (c) => unawaited(_player.seek(c.start)),
    );
  }

  /// The chapter the playhead is in: the last one that has started.
  YoutubeChapter? get _currentChapter {
    final pos = _player.state.position;
    YoutubeChapter? found;
    for (final c in widget.chapters) {
      if (c.start <= pos) {
        found = c;
      } else {
        break;
      }
    }
    return found;
  }

  Future<void> _showSubtitleMenu() async {
    final l = AppLocalizations.of(context);
    await _sheet<YoutubeCaption?>(
      title: l.playerSubtitles,
      options: [null, ..._captions], // null = Off
      isSelected: (c) => c?.code == _caption?.code,
      label: (c) => c?.displayLabel ?? l.commonOff,
      onSelect: (c) => unawaited(_setCaption(c)),
    );
  }

  /// Opens a video stream, attaching the external audio track in adaptive mode.
  /// PERF DIAGNOSTIC: times a 3MB range read of the chosen video URL and
  /// compares it to the stream's bitrate. A ratio near 1x means googlevideo is
  /// throttling us to ~real-time (the likely buffering cost); a high ratio
  /// clears throttling and points the finger at mpv probe / dual-open instead.
  Future<void> _probeThrottle(String url, int streamBitrateBps, Stopwatch sw) async {
    final startedAt = sw.elapsedMilliseconds;
    final dio = Dio();
    try {
      final t = Stopwatch()..start();
      final res = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=0-${3 * 1024 * 1024 - 1}'},
        ),
      );
      var bytes = 0;
      await for (final chunk in res.data!.stream) {
        bytes += chunk.length;
        if (bytes >= 3 * 1024 * 1024) break;
      }
      final ms = t.elapsedMilliseconds;
      final double kbps = ms > 0 ? bytes * 8 / ms : 0;
      final double streamKbps = streamBitrateBps / 1000;
      final double ratio = streamKbps > 0 ? kbps / streamKbps : 0;
      debugPrint(
          '[yt-perf] video-url throughput ${kbps.toStringAsFixed(0)} kbit/s '
          'vs stream ${streamKbps.toStringAsFixed(0)} kbit/s = '
          '${ratio.toStringAsFixed(1)}x (${(bytes / 1024).round()}KB in ${ms}ms, '
          'fired at ${startedAt}ms) '
          '${ratio < 1.5 ? "-> LIKELY THROTTLED" : "-> not throttled"}');
    } catch (e) {
      debugPrint('[yt-perf] throttle probe failed: $e');
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _playAdaptive(YtQuality q, [Stopwatch? sw]) async {
    await _player.open(Media(q.url));
    if (sw != null) debugPrint('[yt] video open() issued at ${sw.elapsedMilliseconds}ms');
    if (_audioUrl != null) {
      await _player.setAudioTrack(AudioTrack.uri(_audioUrl!));
      if (sw != null) debugPrint('[yt] audio-add issued at ${sw.elapsedMilliseconds}ms');
    }
    // open() resets tracks, so a chosen subtitle has to be reapplied or it
    // silently vanishes when the viewer changes quality.
    final c = _caption;
    if (c != null) {
      try {
        await _player.setSubtitleTrack(
            SubtitleTrack.uri(c.vttUrl, title: c.label, language: c.code));
      } catch (_) {}
    }
  }

  /// If adaptive playback hasn't started shortly, drop to the muxed stream so
  /// playback never just sits on a black screen.
  void _armFallback() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 9), () {
      if (mounted && !_ready && !_fellBack) _fallbackToMuxed();
    });
  }

  Future<void> _fallbackToMuxed() async {
    final muxed = _streams.muxedUrl;
    if (muxed == null) return;
    _fellBack = true;
    _audioUrl = null;
    if (mounted) {
      setState(() {
        _qualities = _streams.muxedQualities;
        _qualityLabel = 'Auto';
      });
    }
    try {
      await _player.open(Media(muxed));
    } catch (_) {}
  }

  @override
  void activate() {
    super.activate();
    // A GlobalKey just moved this player to a new spot in the tree (the watch
    // page restructured its layout). It's a reparent, not a removal, so cancel
    // the pending pause that deactivate() armed.
    _deactivating = false;
  }

  @override
  void deactivate() {
    // Handed to the dock: it owns playback now, so don't pause on the way out.
    if (_minimized) {
      super.deactivate();
      return;
    }
    // Leaving the tree. Silence immediately rather than waiting for dispose():
    // on Back, dispose() doesn't arrive (the route keeps the page alive), so
    // relying on it leaves audio playing over the rest of the app.
    //
    // But deactivate() also fires when a GlobalKey merely reparents this player
    // (the layout restructure above). Pausing then would freeze a reclaimed
    // video, and pausing while dispose() is tearing the player down races mpv
    // ("Callback invoked after it has been deleted"). So defer: if activate()
    // fires this frame it was a reparent (skip), and if the widget is being
    // disposed it's unmounted by the post-frame (skip; dispose() handles it).
    _deactivating = true;
    final player = _player;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deactivating && mounted) {
        unawaited(() async {
          try {
            await player.pause();
          } catch (_) {}
        }());
      }
    });
    super.deactivate();
  }

  @override
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) routeObserver.subscribe(this, route);
  }

  // Covered by another route (e.g. tapping the channel): pause so audio doesn't
  // keep playing out of sight. Minimizing (below) is the deliberate keep-playing
  // path instead, and going fullscreen (an imperative media_kit push over this
  // page) must not pause either.
  @override
  void didPushNext() {
    if (_minimized) return;
    if (navWatcher.lastPushWasImperative) return; // fullscreen, not a real leave
    _player.pause();
  }

  /// Hand the live player to the floating mini player and leave the screen, so
  /// it keeps playing while you browse (this is the background/PiP path).
  void _minimize() {
    if (_minimized) return;
    _minimized = true;
    _playingSub?.cancel();
    _completedSub?.cancel();
    _sponsorSub?.cancel();
    _fallbackTimer?.cancel();
    _progressTimer?.cancel();
    _reportProgress();
    _volume.dispose();
    final vid = youtubeVideoId(widget.url) ?? '';
    ref.read(pipProvider.notifier).adopt(
          player: _player,
          controller: _controller,
          title: widget.title ?? '',
          matchId: vid,
          route: '/youtube/watch',
          routeExtra: (videoId: vid, title: widget.title),
        );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _statsOpen.dispose();
    // Hand the OS media session back (token-guarded so a newer player wins).
    _mediaSession?.end(_mediaToken);
    _mediaPosSub?.cancel();
    // Ownership was transferred to the PiP dock; don't tear the player down.
    if (_minimized) {
      super.dispose();
      return;
    }
    _volume.dispose();
    _sponsorSub?.cancel();
    _firstFrameSub?.cancel();
    _mpvLogSub?.cancel();
    LivePlayers.remove(_player);
    _fallbackTimer?.cancel();
    _progressTimer?.cancel();
    // Capture the position before teardown, so leaving mid-video keeps the spot.
    _reportProgress();
    _playingSub?.cancel();
    _completedSub?.cancel();
    // Sequence the teardown: stop() and dispose() both mutate the native mpv
    // player, and firing them concurrently makes mpv invoke a callback into a
    // half-freed player ("Callback invoked after it has been deleted"), which
    // aborts the process and leaves the audio running.
    final player = _player;
    unawaited(() async {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }());
    super.dispose();
  }

  void _seekBy(int seconds) {
    final target = _player.state.position + Duration(seconds: seconds);
    final dur = _player.state.duration;
    _player.seek(target < Duration.zero
        ? Duration.zero
        : (target > dur ? dur : target));
  }

  /// Jump a live stream to the live edge (the end of the DVR window).
  void _jumpToLive() {
    final dur = _player.state.duration;
    if (dur > Duration.zero) _player.seek(dur);
  }

  void _bumpVolume(double delta) =>
      _player.setVolume((_player.state.volume + delta).clamp(0.0, 100.0));

  void _toggleMute() {
    final v = _player.state.volume;
    if (v > 0) {
      _preMuteVolume = v;
      _player.setVolume(0);
    } else {
      _player.setVolume(_preMuteVolume == 0 ? 100 : _preMuteVolume);
    }
  }

  /// How the stream is being delivered, for the stats overlay. YouTube is always
  /// direct HTTP streaming; the meaningful distinction is whether it's a separate
  /// high-quality video+audio (adaptive/DASH) or the muxed fallback.
  String _playMethodLabel(AppLocalizations l) =>
      (!_fellBack && _audioUrl != null)
          ? l.playerPlayMethodAdaptive
          : l.playerPlayMethodMuxed;

  Future<void> _changeQuality(YtQuality? q) async {
    final label = q?.label ?? 'Auto';
    if (label == _qualityLabel) return;
    setState(() => _qualityLabel = label);
    final pos = _player.state.position;
    try {
      if (!_fellBack && _audioUrl != null) {
        // Menu "Auto" (q == null) resolves the same bandwidth-aware way.
        final target = q ?? await _autoQuality();
        if (target != null) await _playAdaptive(target);
      } else {
        final url = q?.url ?? (_streams.muxedUrl ?? widget.url);
        await _player.open(Media(url));
      }
      if (pos > Duration.zero) {
        // Wait for the demuxer to report a duration past the target.
        try {
          if (_player.state.duration <= pos) {
            await _player.stream.duration
                .firstWhere((d) => d > pos)
                .timeout(const Duration(seconds: 10));
          }
          await _player.seek(pos);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _showQualityMenu() async {
    final l = AppLocalizations.of(context);
    await _sheet<YtQuality?>(
      title: l.playerQuality,
      options: [null, ..._qualities], // null = Auto
      // 'Auto' is the internal sentinel for the bandwidth-aware pick; display
      // it localized while keeping the real rendition labels (technical) as-is.
      isSelected: (q) => (q?.label ?? 'Auto') == _qualityLabel,
      label: (q) => q?.label ?? l.playerAuto,
      onSelect: _changeQuality,
    );
  }

  Future<void> _showSpeedMenu() async {
    final l = AppLocalizations.of(context);
    await _sheet<double>(
      title: l.playerPlaybackSpeed,
      options: const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
      isSelected: (s) => (s - _player.state.rate).abs() < 0.01,
      label: (s) => s == 1.0 ? l.playerSpeedNormal : '${s}x',
      onSelect: _player.setRate,
    );
  }

  Future<void> _sheet<T>({
    required String title,
    required List<T> options,
    required bool Function(T) isSelected,
    required String Function(T) label,
    required void Function(T) onSelect,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15161A),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          // Cap the sheet and let the options scroll, so a long quality list
          // never overflows.
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        title: Text(label(o),
                            style: const TextStyle(color: Colors.white)),
                        trailing: isSelected(o)
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white)
                            : null,
                        onTap: () {
                          onSelect(o);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // 'YouTube' is a brand name, left untranslated; only the 'Trailer' framing is
  // localized.
  String _titleText(AppLocalizations l) {
    if (widget.title == null) return widget.isTrailer ? l.playerTrailer : 'YouTube';
    return widget.isTrailer ? l.playerTitleTrailer(widget.title!) : widget.title!;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.white70, size: 44),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.white70)),
                  // Some videos can't be extracted at all (e.g. YouTube's
                  // manifestless SABR live streams). Give a one-click way out
                  // rather than a plain dead end.
                  if (isYoutubeUrl(widget.url)) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse(widget.url),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l.playerOpenInBrowser),
                    ),
                  ],
                ],
              ),
            ),
            // Only when standalone (e.g. a trailer). Embedded in the watch page
            // the surrounding page already owns the back button, so a second one
            // over the error box is redundant (and pops nothing useful).
            if (!widget.embedded)
              SafeArea(
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                ),
              ),
          ],
        ),
      );
    }
    // The same keys the Jellyfin player takes, from the same user bindings —
    // the YouTube player had none at all, so space, K, arrows, F and M did
    // nothing on a desktop app. Not focusable when embedded: the page around it
    // owns the keyboard, and stealing focus would break scrolling and search.
    final video = Video(
      controller: _controller,
      controls: (state) => FathomPlayerControls(
        player: _player,
        title: _titleText(l),
        isLive: _isLive,
        barStyle:
            ref.read(preferencesProvider).asData?.value.playerBarStyle ?? 'glass',
        loading: !_ready,
        // Hides itself in the page too, not just fullscreen. A play button and
        // two skip buttons parked over the middle of the video are exactly what
        // you don't want while watching it, and every other player fades them.
        // The pointer being off the video most of the time is the argument FOR
        // this: moving back over it brings them straight back.
        autoHide: true,
        showTopBar: !widget.embedded,
        onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
        onSeekBy: _seekBy,
        onJumpToLive: _isLive ? _jumpToLive : null,
        onToggleMute: _toggleMute,
        onMinimize: widget.embedded ? _minimize : null,
        onToggleTheater: widget.onToggleTheater,
        theaterActive: widget.theaterActive,
        onNext: widget.onNext,
        onSpeed: _showSpeedMenu,
        onQuality: _qualities.isNotEmpty ? _showQualityMenu : null,
        qualityLabel: _qualityLabel == 'Auto' ? l.playerAuto : _qualityLabel,
        onSubtitles: _captions.isNotEmpty ? _showSubtitleMenu : null,
        onChapters: widget.chapters.isNotEmpty ? _showChapterMenu : null,
        statsPlayMethod: _playMethodLabel(l),
        statsOpen: _statsOpen,
        seekBackSeconds: widget.seekBackSeconds,
        seekForwardSeconds: widget.seekForwardSeconds,
        markers: [
          for (final c in widget.chapters)
            (position: c.start, label: c.title),
          for (final s in _sponsors)
            (position: s.start, label: l.playerSkipSegment(s.category.label)),
        ],
      ),
    );
    // On TV, FathomPlayerControls owns the D-pad (arrows walk the control bar).
    // The desktop keyboard shortcuts + autofocus wrapper would intercept the
    // arrows for volume/seek and defeat that, so skip them on TV.
    if (isTvDevice) return video;
    return CallbackShortcuts(
      bindings: _shortcuts(context),
      child: Focus(
        autofocus: !widget.embedded,
        child: video,
      ),
    );
  }

  /// Mirrors the Jellyfin player's bindings, including the user's own, so one
  /// muscle memory works in both. Seeking uses the YouTube skip durations.
  Map<ShortcutActivator, VoidCallback> _shortcuts(BuildContext context) {
    final keys =
        ref.read(preferencesProvider).asData?.value.effectiveKeys ??
            defaultKeyBindings();
    SingleActivator a(String id) =>
        SingleActivator(LogicalKeyboardKey(keys[id]!));
    return {
      const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
          _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (isFullscreen(context)) toggleFullscreen(context);
      },
      // Theater mode, like YouTube's 'T'. Non-fullscreen only, matching both
      // YouTube and where the control-bar button is shown.
      const SingleActivator(LogicalKeyboardKey.keyT): () {
        if (widget.onToggleTheater != null && !isFullscreen(context)) {
          widget.onToggleTheater!();
        }
      },
      a('playPause'): _player.playOrPause,
      a('seekBackward'): () => _seekBy(-widget.seekBackSeconds),
      a('seekForward'): () => _seekBy(widget.seekForwardSeconds),
      a('volumeUp'): () => _bumpVolume(5),
      a('volumeDown'): () => _bumpVolume(-5),
      a('mute'): _toggleMute,
      a('fullscreen'): () => toggleFullscreen(context),
    };
  }
}

/// Full-screen player, used for trailers.
class YoutubePlayerScreen extends StatelessWidget {
  final String url;
  final String? title;
  final bool isTrailer;

  const YoutubePlayerScreen({
    super.key,
    required this.url,
    this.title,
    this.isTrailer = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: YoutubeVideoPlayer(url: url, title: title, isTrailer: isTrailer),
      );
}

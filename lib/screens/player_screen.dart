import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../widgets/player_controls.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/admin_providers.dart';
import '../models/media_segment.dart';
import '../models/session.dart';
import '../services/diagnostics.dart';
import '../widgets/cast_button.dart';
import '../widgets/cast_remote.dart';
import '../state/audio_player.dart';
import '../state/cast.dart';
import '../state/downloads.dart';
import '../state/preferences.dart';
import '../state/library_providers.dart';
import '../state/pip_controller.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../state/syncplay.dart';
import '../state/syncplay_session.dart';
import '../state/volume_sync.dart';
import '../widgets/live_record_button.dart';
import '../widgets/live_info_panel.dart';
import '../services/live_players.dart';
import '../services/live_streams.dart';

/// Full-screen libmpv-backed player. Direct-streams the original file (mpv
/// handles the codecs), resumes from the saved position, and reports progress
/// so the server's Continue Watching stays in sync.
class PlayerScreen extends ConsumerStatefulWidget {
  final BaseItemDto item;
  final bool resume; // false = play from the beginning
  const PlayerScreen({super.key, required this.item, this.resume = true});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

// The skip amounts, matching FathomPlayerControls' defaults. Named constants so
// the buttons and the keyboard can't drift apart.
const int _kSeekBack = 10;
const int _kSeekForward = 30;

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  // Reclaimed a still-playing player from the mini dock (skip re-opening); and
  // handed the player TO the dock (dispose/deactivate must leave it alone).
  bool _reclaimed = false;
  bool _minimized = false;
  late final VolumeSync _volume = VolumeSync(
    player: _player,
    read: () => ref.read(preferencesProvider).asData?.value.volume ?? 100,
    write: (v) => ref
        .read(preferencesProvider.notifier)
        .edit((x) => x.copyWith(volume: v)),
  );
  double _preMuteVolume = 100;
  Timer? _progressTimer;
  Timer? _loadTimer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _buffSub;
  StreamSubscription<String>? _errorSub;
  // SyncPlay ("watch together"): while true, player state changes came from an
  // applied group command, so don't echo them back and cause a loop.
  bool _groupSuppress = false;
  // Set the moment the screen leaves the tree. During deactivate() the element
  // is still `mounted` but no longer active, so ref/provider lookups throw; a
  // late position-stream event must bail on this, not just on `mounted`.
  bool _deactivated = false;
  Timer? _groupSuppressTimer;
  Timer? _buffDebounce;
  bool _reportedBuffering = false;
  // SyncPlay visual cue: 'sync' (waiting/aligning, persistent), 'fwd'/'back'
  // (SkipToSync flash). Mirrors the official client's overlay.
  String? _syncCue;
  Timer? _syncCueTimer;
  Duration _lastPos = Duration.zero;
  bool _started = false;
  // Set the instant dispose() begins so late async callbacks (a scheduled
  // SyncPlay command, a seek that was awaiting the duration) don't touch the
  // torn-down player and throw "[Player] has been disposed".
  bool _disposed = false;
  bool _isPlaying = false;
  // Resolves what to hand the chosen video Cast target (only video-capable
  // receivers are offered): a direct-play file when the codecs fit a Cast
  // device (raw URL + container MIME, so an h264/aac MKV casts as-is), else an
  // HLS transcode.
  Future<({String url, String contentType})?> _castMedia() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return null;
    try {
      return await ref.read(jellyfinClientProvider).castStream(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            itemId: widget.item.id,
          );
    } catch (_) {
      return null;
    }
  }

  /// The current title for the cast screen: the episode being cast (updates as
  /// you skip on the device) or the item's title.
  String _castTitle() =>
      (_epIndex >= 0 && _epIndex < _episodes.length)
          ? _episodes[_epIndex].name
          : _title;

  /// A blurred backdrop for the cast screen: the item's primary image.
  String? _castArtworkUrl() {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || widget.item.primaryImageTag == null) return null;
    return ref.read(jellyfinClientProvider).imageUrl(
          baseUrl: session.baseUrl,
          itemId: widget.item.id,
          type: 'Primary',
          tag: widget.item.primaryImageTag,
        );
  }

  /// Cast a sibling episode: load its stream onto the receiver (single-item, so
  /// this replaces what's playing) and track the new index for skip + title.
  Future<void> _castEpisodeAt(int i) async {
    if (i < 0 || i >= _episodes.length) return;
    final ep = _episodes[i];
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    try {
      final media = await ref.read(jellyfinClientProvider).castStream(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            itemId: ep.id,
          );
      await ref.read(castControllerProvider.notifier).loadMedia(
            url: media.url,
            contentType: media.contentType,
            title: ep.name,
          );
      if (mounted) setState(() => _epIndex = i);
    } catch (_) {}
  }

  // True while the video is floating in a system Picture-in-Picture window
  // (Android). The on-screen controls hide themselves so the PiP window shows
  // just the video.
  bool _inPip = false;
  bool _triedTranscode = false;
  bool _appliedTracks = false;
  String? _error;
  String? _liveStreamId;
  String? _livePlaySessionId;
  List<MediaSegment> _segments = const [];
  MediaSegment? _activeSkip;
  final Set<int> _autoSkipped = {};

  // Sibling episodes, for the Previous/Next episode buttons (TV episodes only).
  List<BaseItemDto> _episodes = const [];
  int _epIndex = -1;
  StreamSubscription<Duration>? _positionSub;
  // Verbose libmpv log capture, only active when Diagnostic logging is on.
  StreamSubscription<PlayerLog>? _logSub;
  // Audio interruptions (headphone unplug, phone call, focus loss) — media_kit
  // doesn't manage these for a bare player, so pause the video on them.
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptSub;
  StreamSubscription<dynamic>? _tracksSub;
  StreamSubscription<bool>? _completedSub;
  // Captured while alive so dispose() never has to touch ref (which throws).
  Session? _session;
  JellyfinClient? _client;
  // Held so dispose() can decrement the open-player count without ref.
  SyncPlaySession? _syncSessionRef;
  // Selected max bitrate in bits/sec; 0 = Auto (direct play).
  int _qualityBitrate = 0;
  // Trickplay (scrub-preview) geometry + live hover state over the seek bar.
  TrickplayInfo? _trickplay;
  int? _trickWidth;

  /// Phones/tablets only: a dedicated video screen belongs in landscape with the
  /// system bars out of the way, like every other mobile player. No-op on
  /// desktop, where media_kit's window fullscreen handles this instead.
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  void _enterImmersiveLandscape() {
    if (!_isMobile) return;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    if (!_isMobile) return;
    // Empty list = no lock (restore whatever the app allowed before), and bring
    // the status/nav bars back edge-to-edge.
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Pause the video on audio interruptions the way any media app should: a
  /// headphone/Bluetooth disconnect ("becoming noisy"), or another app / a call
  /// taking audio focus. Mobile only; media_kit doesn't do this for us.
  Future<void> _setupAudioSession() async {
    if (!_isMobile) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (!_disposed && !_deactivated) _safePause();
      });
      _interruptSub = session.interruptionEventStream.listen((e) {
        if (_disposed || _deactivated) return;
        if (e.begin && _isPlaying) _safePause();
      });
      await session.setActive(true);
    } catch (_) {}
  }

  // System Picture-in-Picture (Android). The native side floats the activity
  // into a PiP window on Home while [_pipChannel]'s "setActive" flag is set,
  // and reports mode changes back so we can hide the controls.
  static const _pipChannel = MethodChannel('app.fathom.player/pip');

  void _enableSystemPip() {
    if (!Platform.isAndroid) return;
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged' && mounted) {
        final inPip = call.arguments as bool? ?? false;
        setState(() => _inPip = inPip);
        // In a PiP window the system owns sizing/orientation; the fullscreen
        // landscape lock + immersive bars fight it and cause jank (worse the
        // second time, after the in-app dock has already reset orientation).
        // Drop the lock while floating, restore the immersive look on return.
        if (inPip) {
          _restoreSystemUi();
        } else {
          _enterImmersiveLandscape();
        }
      }
    });
    _pipChannel.invokeMethod('setActive', true);
  }

  void _disableSystemPip() {
    if (!Platform.isAndroid) return;
    _pipChannel.invokeMethod('setActive', false);
    _pipChannel.setMethodCallHandler(null);
  }

  @override
  void initState() {
    super.initState();
    _enterImmersiveLandscape();
    _enableSystemPip();
    _setupAudioSession();
    // Reopening from the mini dock: take back the still-playing player instead
    // of opening the stream again. Read the dock's fields here but defer the
    // state change (mutating a provider in initState throws).
    final pipNotifier = ref.read(pipProvider.notifier);
    final dockedPlayer = pipNotifier.player;
    final dockedController = pipNotifier.controller;
    final canReclaim = dockedPlayer != null &&
        dockedController != null &&
        ref.read(pipProvider).matchId == widget.item.id;
    if (canReclaim) {
      _player = dockedPlayer;
      _controller = dockedController;
      _reclaimed = true;
      // Take back the open live-stream handles so this screen can release the
      // tuner on Back (it stays registered with LiveStreams throughout).
      final data = pipNotifier.handoffData;
      if (data is ({String? liveStreamId, String? playSessionId})) {
        _liveStreamId = data.liveStreamId;
        _livePlaySessionId = data.playSessionId;
      }
      WidgetsBinding.instance
          .addPostFrameCallback((_) => pipNotifier.detachForReclaim());
    } else {
      // With Diagnostic logging on, spin the player up with a verbose libmpv
      // logger and pipe its lines into the diagnostics buffer so a real decode
      // trace (codec, hwdec path, vo, frame drops) can be exported later.
      final diag =
          ref.read(preferencesProvider).asData?.value.diagnosticLogging ??
              false;
      _player = Player(
        configuration: PlayerConfiguration(
          // Verbose, not debug: verbose keeps the decoder/hwdec/VO selection,
          // fps, and warnings readable, where debug floods per-frame timing and
          // scrolls the useful startup lines out of the ring buffer in seconds.
          logLevel: diag ? MPVLogLevel.v : MPVLogLevel.error,
        ),
      );
      _controller = VideoController(_player);
      if (diag) {
        Diagnostics.instance.enabled = true;
        _logSub = _player.stream.log.listen((e) => Diagnostics.instance
            .add('mpv', '${e.prefix} [${e.level}] ${e.text}'));
      }
      // A different video (or none) may be docked; silence it after this frame.
      if (dockedPlayer != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => pipNotifier.close());
      }
    }
    // Track this player for SyncPlay follow (so a group item switch replaces it
    // instead of stacking a second player that keeps playing underneath).
    final syncSession = ref.read(syncPlaySessionProvider);
    _syncSessionRef = syncSession;
    syncSession.notifyPlayerOpened();
    // Volume is shared and remembered across every player.
    _volume.attach();
    // Quitting outright skips dispose(); the registry tears mpv down
    // before the engine goes. A reclaimed player is already registered.
    if (!_reclaimed) LivePlayers.add(_player);
    final mbps = ref.read(preferencesProvider).asData?.value.maxBitrateMbps ?? 0;
    _qualityBitrate = mbps > 0 ? mbps * 1000000 : 0;
    _errorSub = _player.stream.error.listen((e) {
      if (!mounted) return;
      _maybeFallbackOrError(
          AppLocalizations.of(context).playerPlaybackError(e.toString()));
    });
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing && !_isPlaying) {
        _isPlaying = true;
        _loadTimer?.cancel();
        if (mounted) setState(() {});
      }
      // Any actual playback clears a persistent "syncing/waiting" cue.
      if (playing && _syncCue == 'sync') _clearSyncCue();
      // Drive the SyncPlay group on a user-initiated play/pause. Gated on
      // _started so the paused/playing flips during initial load (especially a
      // sync open, which starts paused) don't broadcast a spurious pause/unpause
      // to the whole group. Live is included — its play/pause state only changes
      // on a real user action (buffering rides a separate stream), so pausing a
      // live channel propagates to the group too.
      if (_started && !_groupSuppress && _inGroup) {
        final session = ref.read(syncPlaySessionProvider);
        playing ? session.unpause() : session.pause();
      }
    });
    _positionSub = _player.stream.position.listen(_onPosition);
    _tracksSub = _player.stream.tracks.listen((_) => _applyDefaultTracks());
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _onCompleted();
    });
    // Report buffering/ready to the group so everyone waits for a slow member.
    // Debounced: only a stall that lasts a beat is reported, so media_kit's
    // transient buffering toggles (around every seek) don't yo-yo the group.
    _buffSub = _player.stream.buffering.listen((buffering) {
      if (widget.item.isLiveChannel || !_inGroup) return;
      final session = ref.read(syncPlaySessionProvider);
      // Skip until we know the group's PlaylistItemId — a Buffering/Ready with
      // the wrong id is rejected by the server and re-marks us buffering.
      if (session.currentPlaylistItemId == null) return;
      _buffDebounce?.cancel();
      if (buffering) {
        _buffDebounce = Timer(const Duration(milliseconds: 350), () {
          if (!_inGroup || !_player.state.buffering) return;
          _reportedBuffering = true;
          session.reportBuffering(_player.state.position,
              playing: _player.state.playing);
        });
      } else if (_reportedBuffering) {
        _reportedBuffering = false;
        session.reportReady(_player.state.position,
            playing: _player.state.playing);
      }
    });
    if (_reclaimed) {
      // Already playing: restore the server session context and resume progress
      // reporting, but don't reopen or re-report a start.
      _resumeAfterReclaim();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  /// Re-establish the bits [_start] set up, for a player taken back from the
  /// dock (which is already open and playing).
  void _resumeAfterReclaim() {
    _session = ref.read(sessionControllerProvider).asData?.value;
    _client = ref.read(jellyfinClientProvider);
    _started = true;
    _isPlaying = _player.state.playing;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _reportProgress());
    // Repopulate the scrub-preview and intro/credit skips lost with the old
    // screen (best-effort; playback is unaffected if they don't come back).
    final s = _session, c = _client;
    if (s != null && c != null && !widget.item.isLiveChannel) {
      c
          .getMediaSegments(
              baseUrl: s.baseUrl, token: s.accessToken, itemId: widget.item.id)
          .then((seg) {
        if (mounted) _segments = seg;
      }).catchError((_) {});
      _loadTrickplay(c, s);
    }
  }

  // Jellyfin ticks are 100ns units: 1 microsecond = 10 ticks.
  int get _positionTicks => _player.state.position.inMicroseconds * 10;

  /// The context queue to broadcast when INITIATING group playback of this item,
  /// matching the official client: for an episode, the whole series' episodes in
  /// order (with this one's index); for anything else, a single-item queue. A
  /// lone-item queue makes jellyfin-web's reconciliation throw and refuse to
  /// switch, so the surrounding queue is what actually makes the other device
  /// follow. Followers skip this (setNewQueue is a no-op for them).
  Future<(List<String>, int)> _buildGroupQueue() async {
    final item = widget.item;
    final s = _session, c = _client;
    if (item.isEpisode &&
        (item.seriesId?.isNotEmpty ?? false) &&
        s != null &&
        c != null &&
        !ref.read(syncPlaySessionProvider).isFollowOpen(item.id)) {
      try {
        final eps = await c.getEpisodes(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            seriesId: item.seriesId!);
        final ids = [for (final e in eps) e.id];
        final idx = ids.indexOf(item.id);
        if (idx >= 0) return (ids, idx);
      } catch (_) {}
    }
    return ([item.id], 0);
  }

  Future<void> _start() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null) return;
    final l = AppLocalizations.of(context);
    _session = session;
    _client = client;
    unawaited(_loadSiblingEpisodes());

    // Don't let background music play under the video.
    if (ref.read(audioControllerProvider).hasTrack) {
      await ref.read(audioPlayerProvider).pause();
    }

    try {
      final String url;
      if (widget.item.isLiveChannel) {
        final handle = await client.openLiveStream(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          channelId: widget.item.id,
        );
        url = handle.url;
        _liveStreamId = handle.liveStreamId;
        _livePlaySessionId = handle.playSessionId;
        // Registered so quitting mid-channel still hands the tuner back.
        final s = _session, c = _client;
        if (handle.liveStreamId != null && s != null && c != null) {
          LiveStreams.register(OpenLiveStream(
            client: c,
            session: s,
            liveStreamId: handle.liveStreamId!,
            playSessionId: handle.playSessionId,
          ));
        }
      } else {
        url = await _videoUrlForQuality();
      }
      // Apply hardware-decoding preference before the file loads. Live TV on
      // mobile forces software decoding regardless: the hardware VPU chokes on
      // the real-time HLS transcode ("VPU reported error 0x100000" every frame,
      // so nothing renders and play/pause looks dead), while libavcodec on the
      // CPU decodes it fine. VOD is unaffected (a well-formed file decodes fine
      // in hardware).
      final startPrefs = ref.read(preferencesProvider).asData?.value;
      final forceSoftware = _isMobile && widget.item.isLiveChannel;
      if (forceSoftware ||
          (startPrefs != null && !startPrefs.hardwareDecoding)) {
        try {
          await (_player.platform as dynamic).setProperty('hwdec', 'no');
        } catch (_) {}
      }
      // Give mpv a generous network cache and read-ahead. media_kit leaves these
      // at libmpv's defaults, which are tuned for local files, so streaming
      // starts slowly and every seek that lands outside a tiny window re-fetches
      // from the network. A larger demuxer cache (with back-buffer) makes start
      // quicker and in-buffer seeks instant.
      try {
        final mpv = _player.platform as dynamic;
        await mpv.setProperty('cache', 'yes');
        await mpv.setProperty('demuxer-max-bytes', '150MiB');
        await mpv.setProperty('demuxer-max-back-bytes', '75MiB');
        await mpv.setProperty('demuxer-readahead-secs', '30');
        await mpv.setProperty('cache-secs', '30');
        await mpv.setProperty('network-timeout', '30');
      } catch (_) {}
      // Optional smoother motion: pace frames to the monitor refresh instead of
      // libmpv's default audio-clock sync, and interpolate across non-integer
      // fps/refresh ratios (the 24fps-on-60Hz judder). Desktop only (mobile
      // renders through the platform mediacodec surface, not this GL path), and
      // opt-in because on setups already smooth it's a no-op or a small cost.
      if (!_isMobile && (startPrefs?.displaySync ?? false)) {
        try {
          final mpv = _player.platform as dynamic;
          await mpv.setProperty('video-sync', 'display-resample');
          await mpv.setProperty('interpolation', 'yes');
          await mpv.setProperty('tscale', 'oversample');
        } catch (_) {}
      }
      // In a SyncPlay group (VOD): a FOLLOWER (we opened this because the group
      // switched to it) opens PAUSED and waits for the server's synchronized
      // Unpause. An INITIATOR (user picked this) plays immediately so it doesn't
      // feel dead. Either way we report Ready; the server auto-broadcasts Unpause
      // once all members are ready (we never send a manual play request — that
      // mishandled a freshly-Idle group).
      final syncSession = ref.read(syncPlaySessionProvider);
      final inGroupVod = !widget.item.isLiveChannel && _inGroup;
      final syncing = inGroupVod && syncSession.isFollowOpen(widget.item.id);
      if (Diagnostics.instance.enabled) {
        Diagnostics.instance.add(
            'playback',
            'open "${widget.item.name}" live=${widget.item.isLiveChannel} '
                'transcode=$_triedTranscode hwdec='
                '${startPrefs?.hardwareDecoding ?? true} '
                'url=${redactUrl(url)}');
      }
      await _player.open(Media(url), play: !syncing);

      final prefs = ref.read(preferencesProvider).asData?.value;
      if (prefs != null && prefs.subtitleScale != 1.0) {
        try {
          await (_player.platform as dynamic)
              .setProperty('sub-scale', prefs.subtitleScale.toString());
        } catch (_) {}
      }
      if (prefs != null && prefs.subtitlePosition != 100) {
        try {
          await (_player.platform as dynamic)
              .setProperty('sub-pos', prefs.subtitlePosition.toString());
        } catch (_) {}
      }
      // Apply the default playback speed (Live TV always plays at 1x).
      if (prefs != null &&
          prefs.playbackSpeed != 1.0 &&
          !widget.item.isLiveChannel) {
        try {
          await _player.setRate(prefs.playbackSpeed);
        } catch (_) {}
      }

      if (!widget.item.isLiveChannel) {
        client
            .getMediaSegments(
                baseUrl: session.baseUrl,
                token: session.accessToken,
                itemId: widget.item.id)
            .then((s) {
          if (mounted) _segments = s;
        });
        _loadTrickplay(client, session);
      }

      // If nothing has started playing in a while, fall back or explain.
      _loadTimer = Timer(const Duration(seconds: 25), () {
        _maybeFallbackOrError(widget.item.isLiveChannel
            ? l.playerChannelSlowStart
            : l.playerVideoSlowStart);
      });

      final resumeTicks =
          widget.resume ? widget.item.resumePositionTicks : 0;
      // Where to start:
      // - FOLLOWER: the group's current position.
      // - INITIATOR in a group: from the BEGINNING (0). Broadcasting a deep
      //   resume point makes every follower cold-seek a fresh stream to that
      //   spot, which they can't do fast enough — the group then thrashes and
      //   resets (the observed Seek-to-0). Starting at 0 keeps everyone aligned;
      //   anyone can seek together once playing.
      // - SOLO (not in a group): our own resume point.
      // A FOLLOWER joins at the group's current position; an INITIATOR (and solo
      // playback) start at our resume point and BROADCAST it as the queue's
      // StartPositionTicks — so every member's transcode simply begins there,
      // with no mid-stream cold-seek (which is what thrashed the group).
      Duration startAt = Duration(microseconds: resumeTicks ~/ 10);
      if (syncing && syncSession.groupStartPosition > Duration.zero) {
        startAt = syncSession.groupStartPosition;
      }
      if (startAt > Duration.zero) {
        _suppressGroup(); // this seek isn't a user action; don't broadcast it
        await _seekWhenReady(startAt);
      }

      _started = true;
      // Telling the server "I started" is bookkeeping for resume-sync, not part
      // of playback. Its failure must never surface as a playback error — a
      // downloaded file plays perfectly with the server unreachable, and it did
      // so while this call, awaited here, put an error screen over a video that
      // was already playing.
      unawaited(_reportStartQuietly(client, session, resumeTicks));
      if (inGroupVod) {
        // Set the queue (broadcasts a full context queue if we initiated; no-op
        // echo if following), then report READY — but only after the media has
        // loaded AND the server's PlaylistItemId is known (it arrives on the
        // echoed PlayQueue update). A Ready sent too early is rejected and we'd
        // stay buffering forever, stalling the whole group. Once every member is
        // ready the server auto-broadcasts Unpause; we don't request play.
        final (queue, pos) = await _buildGroupQueue();
        unawaited(syncSession.setNewQueue(queue, pos, startAt).then((_) {
          _reportReadyWhenLoaded(startAt, playing: !syncing);
        }));
        // Only a follower waits — show the syncing cue until the group plays us.
        if (syncing) _setSyncCue('sync');
      } else if (_inGroup && widget.item.isLiveChannel) {
        // Live TV in a group: broadcast the channel so members follow to it; it
        // plays at the live edge, so report ready-and-playing once loaded. The
        // server coordinates from there.
        unawaited(syncSession
            .setNewQueue([widget.item.id], 0, Duration.zero).then((_) {
          _reportReadyWhenLoaded(Duration.zero, playing: true);
        }));
      } else {
        syncSession.setLocalItem(widget.item.id);
      }
      _progressTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => _reportProgress());
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = l.playerPlaybackFailed('$e'));
    }
  }

  Future<void> _reportStartQuietly(
      dynamic client, dynamic session, int resumeTicks) async {
    try {
      await client.reportPlaybackStart(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        itemId: widget.item.id,
        positionTicks: resumeTicks,
      );
    } catch (_) {
      // Offline, or the server hiccuped: playback carries on regardless.
    }
  }

  /// Loads trickplay geometry for the scrub-preview. The list item passed in
  /// rarely carries it, so fetch the full item unless it's already present.
  Future<void> _loadTrickplay(JellyfinClient client, Session session) async {
    var info = widget.item.trickplayInfo;
    var width = widget.item.trickplayWidth;
    if (info == null) {
      try {
        final full = await client.getItem(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: widget.item.id,
        );
        info = full.trickplayInfo;
        width = full.trickplayWidth;
      } catch (_) {
        return;
      }
    }
    if (info != null && width != null && mounted) {
      setState(() {
        _trickplay = info;
        _trickWidth = width;
      });
    }
  }

  /// Resolves the stream URL for the current quality: an offline copy if
  /// downloaded, a bitrate-capped transcode when a quality is chosen, else a
  /// direct stream.
  Future<String> _videoUrlForQuality() async {
    final local =
        ref.read(downloadsProvider.notifier).localPathFor(widget.item.id);
    if (local != null) return local;
    final client = _client!, session = _session!;
    if (_qualityBitrate > 0) {
      // Pass the bitrate cap but let the server direct-play when the source is
      // already under it; it only transcodes when a real downscale is needed.
      return client.openVideoStream(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: widget.item.id,
        maxBitrate: _qualityBitrate,
      );
    }
    return client.videoStreamUrl(
      baseUrl: session.baseUrl,
      itemId: widget.item.id,
      token: session.accessToken,
    );
  }

  /// Switch streaming quality mid-playback: remember the position, reopen the
  /// stream at the new bitrate, and resume where we were.
  Future<void> _changeQuality(int bitrate) async {
    if (bitrate == _qualityBitrate || widget.item.isLiveChannel) return;
    final l = AppLocalizations.of(context);
    final pos = _player.state.position;
    setState(() => _qualityBitrate = bitrate);
    try {
      final url = await _videoUrlForQuality();
      await _player.open(Media(url));
      _appliedTracks = false;
      if (pos > Duration.zero) {
        _suppressGroup(); // reopening at the same spot isn't a group seek
        await _seekWhenReady(pos);
      }
    } catch (e) {
      if (mounted) setState(() => _error = l.playerQualityChangeFailed('$e'));
    }
  }

  /// Seeks once the demuxer reports a duration past the target, so mpv doesn't
  /// drop an early seek issued before the media is loaded.
  Future<void> _seekWhenReady(Duration target) async {
    try {
      if (_player.state.duration <= target) {
        await _player.stream.duration
            .firstWhere((d) => d > target)
            .timeout(const Duration(seconds: 15));
      }
      if (_disposed) return;
      await _player.seek(target);
    } catch (_) {
      // Duration never arrived (odd media) — leave playback at the start.
    }
  }

  /// On playback failure for a regular video, retry once via server transcode
  /// before giving up. Live channels don't fall back this way.
  void _maybeFallbackOrError(String reason) {
    if (!mounted || _isPlaying) return;
    if (!widget.item.isLiveChannel && !_triedTranscode) {
      _triedTranscode = true;
      _retryWithTranscode();
    } else {
      setState(() => _error ??= reason);
    }
  }

  Future<void> _retryWithTranscode() async {
    final session = _session;
    final client = _client;
    if (session == null || client == null) return;
    final l = AppLocalizations.of(context);
    try {
      final url = await client.openVideoStream(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: widget.item.id,
        forceTranscode: true,
      );
      await _player.open(Media(url));
      final resumeTicks = widget.item.resumePositionTicks;
      if (resumeTicks > 0) {
        _suppressGroup(); // transcode-fallback resume isn't a group seek
        await _seekWhenReady(Duration(microseconds: resumeTicks ~/ 10));
      }
      _loadTimer?.cancel();
      _loadTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && !_isPlaying) {
          setState(() => _error ??= l.playerVideoUnplayable);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = l.playerPlaybackFailed('$e'));
    }
  }

  // The playing/buffering/position streams can each fire once more while the
  // screen is being torn down; reading a provider from a deactivated element
  // throws, so gate on both flags (mounted alone is still true in deactivate()).
  bool get _inGroup =>
      mounted && !_deactivated && ref.read(syncPlayControllerProvider);

  /// Ignore player state changes for a beat so an applied group command (or our
  /// own auto-skip) isn't echoed back to the group.
  void _suppressGroup() {
    _groupSuppress = true;
    _groupSuppressTimer?.cancel();
    _groupSuppressTimer =
        Timer(const Duration(milliseconds: 900), () => _groupSuppress = false);
  }

  void _onPosition(Duration pos) {
    // The position stream can deliver one more event while the screen is torn
    // down; touching ref/providers then looks up a deactivated widget. Bail on
    // both flags — `mounted` is still true during deactivate().
    if (!mounted || _deactivated) return;
    // A jump (not normal progression) is a user seek — drive the group.
    if (!widget.item.isLiveChannel && _inGroup && !_groupSuppress) {
      if ((pos - _lastPos).abs() > const Duration(milliseconds: 2500)) {
        ref.read(syncPlaySessionProvider).seek(pos);
      }
    }
    _lastPos = pos;
    if (widget.item.isLiveChannel || _segments.isEmpty) return;
    MediaSegment? active;
    for (final s in _segments) {
      if (s.isSkippable && s.contains(pos)) {
        active = s;
        break;
      }
    }
    if (active != null) {
      final prefs = ref.read(preferencesProvider).asData?.value;
      final auto = (active.isIntro && (prefs?.autoSkipIntro ?? false)) ||
          (active.isCredits && (prefs?.autoSkipCredits ?? false));
      if (auto && !_autoSkipped.contains(active.startTicks)) {
        _autoSkipped.add(active.startTicks);
        // Each member auto-skips on its own; don't broadcast this as a seek.
        _suppressGroup();
        _player.seek(active.end);
        active = null;
      }
    }
    if (active?.startTicks != _activeSkip?.startTicks && mounted) {
      setState(() => _activeSkip = active);
    }
  }

  /// Loads the series' episodes so Previous/Next can step through them. Runs
  /// once on open for an episode; leaves the buttons hidden for anything else.
  Future<void> _loadSiblingEpisodes() async {
    final item = widget.item;
    if (!item.isEpisode || (item.seriesId?.isEmpty ?? true)) return;
    final s = _session, c = _client;
    if (s == null || c == null) return;
    try {
      final eps = await c.getEpisodes(
        baseUrl: s.baseUrl,
        userId: s.userId,
        token: s.accessToken,
        seriesId: item.seriesId!,
      );
      final idx = eps.indexWhere((e) => e.id == item.id);
      if (idx >= 0 && mounted) {
        setState(() {
          _episodes = eps;
          _epIndex = idx;
        });
      }
    } catch (_) {}
  }

  void _playEpisodeAt(int index) {
    if (index < 0 || index >= _episodes.length) return;
    context.pushReplacement('/player', extra: _episodes[index]);
  }

  Future<void> _onCompleted() async {
    if (!mounted || _deactivated) return;
    if (widget.item.isLiveChannel || !widget.item.isEpisode) return;
    final seriesId = widget.item.seriesId;
    if (seriesId == null) return;
    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs?.autoplayNext != true) return;
    final session = _session, client = _client;
    if (session == null || client == null) return;
    try {
      final next = await client.getNextUp(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        seriesId: seriesId,
      );
      if (next != null && next.id != widget.item.id && mounted) {
        context.pushReplacement('/player', extra: next);
      }
    } catch (_) {}
  }

  void _applyDefaultTracks() {
    if (_appliedTracks || widget.item.isLiveChannel) return;
    final tracks = _player.state.tracks;
    if (tracks.audio.length <= 1 && tracks.subtitle.length <= 1) return;
    final prefs = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    _appliedTracks = true;
    if (prefs.audioLanguage.isNotEmpty) {
      final match = tracks.audio.where((t) =>
          (t.language ?? '').toLowerCase().startsWith(prefs.audioLanguage));
      if (match.isNotEmpty) _player.setAudioTrack(match.first);
    }
    if (prefs.subtitleLanguage.isNotEmpty) {
      final match = tracks.subtitle.where((t) =>
          (t.language ?? '').toLowerCase().startsWith(prefs.subtitleLanguage));
      if (match.isNotEmpty) _player.setSubtitleTrack(match.first);
    }
  }

  // Report SyncPlay readiness once the media has loaded AND the server's
  // PlaylistItemId for the current queue item is known (it arrives on the echoed
  // PlayQueue update). Reporting before either is set makes the server keep us
  // buffering, which stalls the whole group's synchronized start.
  Future<void> _reportReadyWhenLoaded(Duration position,
      {required bool playing}) async {
    final session = ref.read(syncPlaySessionProvider);
    try {
      if (_player.state.duration <= Duration.zero) {
        await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 20));
      }
    } catch (_) {}
    // Wait (briefly) for the echoed PlayQueue to deliver the PlaylistItemId.
    for (var i = 0;
        i < 50 && !_disposed && session.currentPlaylistItemId == null;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_disposed || !_inGroup) return;
    unawaited(session.reportReady(position, playing: playing));
  }

  Future<void> _reportProgress() async {
    // Use the captured session/client, NOT ref — this fires from a periodic
    // timer that can outlive the widget being deactivated (e.g. a SyncPlay item
    // switch replacing the player), and ref.read on a deactivated element
    // throws. Guard on _disposed so a late tick is a no-op.
    if (!_started || _disposed) return;
    final session = _session;
    final client = _client;
    if (session == null || client == null) return;
    // Best-effort: this fires every 10s, and offline it would throw every 10s.
    // A missed progress report costs a slightly stale resume point, nothing
    // that should reach the viewer.
    try {
      await client.reportPlaybackProgress(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            itemId: widget.item.id,
            positionTicks: _positionTicks,
          );
    } catch (_) {}
  }

  /// Tell the server we've stopped and hand the tuner back. Idempotent: it
  /// runs from deactivate() and again from dispose(), and must not double-post.
  bool _released = false;

  void _releaseServerSide() {
    if (_released) return;
    _released = true;
    final session = _session;
    final client = _client;
    if (session == null || client == null) return;
    final positionTicks = _positionTicks;
    final liveStreamId = _liveStreamId;

    if (_started) {
      // The live ids are what tell the server which session ended; without
      // them it leaves the tuner and the transcode running.
      unawaited(client.reportPlaybackStopped(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        itemId: widget.item.id,
        positionTicks: positionTicks,
        liveStreamId: liveStreamId,
        playSessionId: _livePlaySessionId,
      ));
    }
    if (liveStreamId != null) {
      unawaited(client.closeLiveStream(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        liveStreamId: liveStreamId,
        playSessionId: _livePlaySessionId,
      ));
      LiveStreams.unregister(liveStreamId);
    }
  }

  /// Hand the live player to the floating mini dock and leave, so it keeps
  /// playing while you browse. Works for on-demand and live TV: for live the
  /// open tuner stays registered and is handed back on reclaim, or released when
  /// the dock is closed.
  void _minimize() {
    if (_minimized || !_started) return;
    _minimized = true;
    _loadTimer?.cancel();
    _progressTimer?.cancel();
    _groupSuppressTimer?.cancel();
    _buffDebounce?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _buffSub?.cancel();
    _positionSub?.cancel();
    _tracksSub?.cancel();
    _completedSub?.cancel();
    // Save a resume point now; while docked there's no screen to report from.
    unawaited(_reportProgress());
    _volume.dispose();
    final itemId = widget.item.id;
    // Captured so the dock can hand the live-stream back on reclaim, and release
    // the tuner on close.
    final liveStreamId = _liveStreamId;
    final livePlaySessionId = _livePlaySessionId;
    ref.read(pipProvider.notifier).adopt(
          player: _player,
          controller: _controller,
          title: widget.item.name,
          matchId: itemId,
          route: '/player',
          routeExtra: widget.item,
          handoffData: (
            liveStreamId: liveStreamId,
            playSessionId: livePlaySessionId,
          ),
          // Closing the dock finalizes the resume point and, for live TV, hands
          // the tuner back so it isn't pinned until the server restarts.
          onClose: (p) async {
            final s = _session, c = _client;
            if (s == null || c == null) return;
            try {
              await c.reportPlaybackStopped(
                baseUrl: s.baseUrl,
                token: s.accessToken,
                itemId: itemId,
                positionTicks: p.state.position.inMicroseconds * 10,
                liveStreamId: liveStreamId,
                playSessionId: livePlaySessionId,
              );
            } catch (_) {}
            if (liveStreamId != null) {
              try {
                await c.closeLiveStream(
                  baseUrl: s.baseUrl,
                  token: s.accessToken,
                  liveStreamId: liveStreamId,
                  playSessionId: livePlaySessionId,
                );
              } catch (_) {}
              LiveStreams.unregister(liveStreamId);
            }
          },
        );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void deactivate() {
    // Leaving the player (backing out OR minimizing to the dock): let the app
    // rotate freely and show the system bars again. Done here, not just
    // dispose(), because dispose isn't guaranteed to run on the way out.
    _restoreSystemUi();
    _disableSystemPip();
    // From here on the element is inactive: block ref use in stream callbacks.
    _deactivated = true;
    // Handed to the dock: it owns playback now, so don't release the session or
    // pause on the way out.
    if (_minimized) {
      super.deactivate();
      return;
    }
    // Leaving the tree. The tuner is released HERE rather than in dispose():
    // dispose() is not guaranteed to run when you back out — that is exactly
    // what left YouTube audio playing after Back — and a missed release pins
    // an HDHomeRun tuner until Jellyfin restarts. Stop the audio here too, for
    // the same reason. Cancel the periodic timers here as well: on a SyncPlay
    // item switch the replaced screen may be deactivated without dispose()
    // running promptly, and a lingering progress timer would keep posting stale
    // progress for the old item every 10s.
    _progressTimer?.cancel();
    _syncCueTimer?.cancel();
    // Suppress the group broadcast: pausing here is local teardown (leaving the
    // player, or switching shows), NOT a user pausing the group. Without this,
    // the stream.playing listener fires session.pause() and wrongly pauses every
    // member mid-switch, fighting the next show's setNewQueue/unpause.
    _groupSuppress = true;
    _groupSuppressTimer?.cancel();
    _releaseServerSide();
    _safePause();
    super.deactivate();
  }

  @override
  void dispose() {
    _disposed = true;
    // The verbose logger belongs to this screen; drop it on either exit path
    // (a handed-off dock player keeps playing but stops feeding diagnostics).
    _logSub?.cancel();
    _noisySub?.cancel();
    _interruptSub?.cancel();
    _syncSessionRef?.notifyPlayerClosed();
    // Ownership transferred to the dock: leave the player, session, and
    // subscriptions (already cancelled in _minimize) alone.
    if (_minimized) {
      super.dispose();
      return;
    }
    _volume.dispose();
    LivePlayers.remove(_player);
    _progressTimer?.cancel();
    _loadTimer?.cancel();
    _groupSuppressTimer?.cancel();
    _buffDebounce?.cancel();
    _syncCueTimer?.cancel();
    _playingSub?.cancel();
    _buffSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _tracksSub?.cancel();
    _completedSub?.cancel();
    // A no-op if deactivate() already did it, which is the normal path.
    _releaseServerSide();
    unawaited(_player.stop());
    _player.dispose();
    super.dispose();
  }

  /// Apply an incoming SyncPlay command (best-effort). Live channels honour
  /// pause/unpause/stop but not seek (there's no free-seeking a live edge).
  void _applySyncCommand(SyncCommand? c) {
    if (c == null || _disposed) return;
    if (!ref.read(syncPlayControllerProvider)) return;
    final isLive = widget.item.isLiveChannel;
    // This change is group-driven; don't echo it back.
    _suppressGroup();
    if (c.position > Duration.zero) _lastPos = c.position;
    switch (c.command) {
      case 'Unpause':
        if (!isLive && c.position > Duration.zero) _safeSeek(c.position);
        _safePlay();
        _clearSyncCue(); // playing in sync now
      case 'Pause':
        _safePause();
        if (!isLive && c.position > Duration.zero) _safeSeek(c.position);
        _setSyncCue('sync'); // group paused / holding to align
      case 'Seek':
        if (isLive) break; // no seeking a live stream
        // Show SkipToSync direction (forward to catch up, back to wait).
        _flashSyncCue(
            c.position > _player.state.position + const Duration(seconds: 1)
                ? 'fwd'
                : c.position < _player.state.position - const Duration(seconds: 1)
                    ? 'back'
                    : 'sync');
        _safeSeek(c.position);
      case 'Stop':
        _safePause();
        _setSyncCue('sync');
    }
  }

  // Fire-and-forget player ops that swallow a post-disposal error. On app quit
  // dispose() is skipped (the registry tears mpv down), so _disposed stays false
  // and a late SyncPlay command would otherwise seek/pause a disposed player and
  // crash with an unhandled async "[Player] has been disposed".
  void _safeSeek(Duration d) {
    _player.seek(d).catchError((_) {});
  }

  void _safePlay() {
    _player.play().catchError((_) {});
  }

  void _safePause() {
    _player.pause().catchError((_) {});
  }

  // Persistent cue (shown until cleared), e.g. waiting for the group to resume.
  void _setSyncCue(String cue) {
    _syncCueTimer?.cancel();
    if (_syncCue != cue && mounted) setState(() => _syncCue = cue);
  }

  // Brief cue (SkipToSync), auto-clears after a beat.
  void _flashSyncCue(String cue) {
    _syncCueTimer?.cancel();
    if (mounted) setState(() => _syncCue = cue);
    _syncCueTimer = Timer(const Duration(milliseconds: 1100), _clearSyncCue);
  }

  void _clearSyncCue() {
    _syncCueTimer?.cancel();
    if (_syncCue != null && mounted) setState(() => _syncCue = null);
  }

  @override
  Widget build(BuildContext context) {
    // Follow SyncPlay commands from the group (experimental, best-effort).
    ref.listen(syncCommandProvider, (_, next) => _applySyncCommand(next));
    // Hand off to a Chromecast: while a cast session is connected, local
    // playback stays paused so audio isn't coming from both the phone and the
    // cast target. Fires on connect, and (via the post-frame guard below) also
    // covers a session that was already live when this player opened.
    ref.listen(castControllerProvider.select((s) => s.casting), (prev, next) {
      if (next == true) {
        _safePause();
      } else if (prev == true) {
        // Cast ended: hand back to local at the position the TV reached, and
        // resume if it was playing (matches the music hand-back).
        final c = ref.read(castControllerProvider);
        if (c.positionMs > 0) _safeSeek(Duration(milliseconds: c.positionMs));
        if (c.playing) _player.play();
      }
    });
    final castStatus = ref.watch(castControllerProvider);
    if (castStatus.casting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && !_deactivated) _safePause();
      });
    }
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).asData?.value;
    final fit = switch (prefs?.playerFit ?? 'contain') {
      'cover' => BoxFit.cover,
      'fill' => BoxFit.fill,
      _ => BoxFit.contain,
    };
    final subtitleConfig = SubtitleViewConfiguration(
      style: TextStyle(
        color: Color(prefs?.subtitleTextColor ?? 0xFFFFFFFF),
        fontSize: 32.0 * (prefs?.subtitleScale ?? 1.0),
        fontWeight: FontWeight.normal,
        backgroundColor: Colors.black
            .withValues(alpha: prefs?.subtitleBackgroundOpacity ?? 0.0),
        shadows: (prefs?.subtitleBackgroundOpacity ?? 0.0) > 0.05
            ? const []
            : const [Shadow(blurRadius: 6, color: Colors.black)],
      ),
      padding: const EdgeInsets.all(24),
    );
    final session = _session;
    final rawQualityLabel = _qualityOptions
        .firstWhere((o) => o.$1 == _qualityBitrate,
            orElse: () => _qualityOptions.first)
        .$2;
    // Only the 'Auto' sentinel is translatable; the resolution/bitrate labels
    // (1080p, Mbps, kbps) are technical tokens left as-is.
    final qualityLabel =
        rawQualityLabel == 'Auto' ? l.playerAuto : rawQualityLabel;

    // Live TV extras, rendered inside the controls so they carry into
    // fullscreen: a rich now-playing panel, and an always-on REC badge.
    final isLive = widget.item.isLiveChannel;
    final program = widget.item.currentProgram;
    // The live now-playing block now lives in the frosted bottom bar (channel
    // identity moved up to the top bar), so the old floating card is gone.
    final liveBottomInfo = isLive
        ? LiveBottomInfo(channelName: widget.item.name, program: program)
        : null;
    final liveRecBadge = (isLive && program != null)
        ? _LiveRecBadge(programId: program.id)
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? _ErrorOverlay(message: _error!)
          : Focus(
              autofocus: true,
              child: CallbackShortcuts(
                bindings: _buildShortcuts(context),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Video(
                        controller: _controller,
                        fit: fit,
                        subtitleViewConfiguration: subtitleConfig,
                        // Controls live inside Video so fullscreen lookups
                        // (toggleFullscreen/isFullscreen) resolve correctly.
                        // In a system PiP window, show just the video (the OS
                        // draws its own play/pause), so hide our chrome.
                        controls: (state) => _inPip
                            ? const SizedBox.shrink()
                            : FathomPlayerControls(
                          player: _player,
                          trickItemId: widget.item.id,
                          title: _title,
                          channelNumber:
                              isLive ? widget.item.channelNumber : null,
                          isLive: widget.item.isLiveChannel,
                          barStyle: prefs?.playerBarStyle ?? 'glass',
                          // On a phone the route is already fullscreen and we
                          // force landscape, so hide the redundant fullscreen
                          // control (and its double-tap gesture).
                          showFullscreen: !_isMobile,
                          // Left-swipe brightness / right-swipe volume, phone only.
                          touchGestures: _isMobile,
                          // Hide the generic spinner while a SyncPlay cue is
                          // shown — the sync glyph is the status indicator then,
                          // and two overlapping spinners just fight for space.
                          loading: !_isPlaying && _syncCue == null,
                          onBack: () => Navigator.of(context).maybePop(),
                          onSeekBy: _seekBy,
                          onJumpToLive: isLive ? _jumpToLive : null,
                          onSubtitles: _showSubtitleMenu,
                          onAudio: _showAudioMenu,
                          // Speed and Quality are meaningless on a live stream
                          // (it always plays at 1x, and there's no transcode
                          // ladder), so both are hidden there.
                          onSpeed: widget.item.isLiveChannel
                              ? null
                              : _showSpeedMenu,
                          onQuality: widget.item.isLiveChannel
                              ? null
                              : _showQualityMenu,
                          qualityLabel: qualityLabel,
                          onChapters: widget.item.chapters.isNotEmpty
                              ? _showChapters
                              : null,
                          markers: [
                            for (final c in widget.item.chapters)
                              (position: c.start, label: c.name ?? l.playerChapter),
                            for (final seg in _segments)
                              (position: seg.start, label: seg.categoryLabel(l)),
                          ],
                          recordButton: (widget.item.isLiveChannel &&
                                  widget.item.currentProgram != null)
                              ? LiveRecordButton(
                                  programId: widget.item.currentProgram!.id)
                              : null,
                          onToggleMute: _toggleMute,
                          trickplay: _trickplay,
                          trickplayWidth: _trickWidth,
                          baseUrl: session?.baseUrl,
                          client: ref.read(jellyfinClientProvider),
                          headers: ref.read(imageHeadersProvider),
                          showThumbnailPreview:
                              prefs?.previewThumbnailsWhileSeeking ?? true,
                          infoPanel: null,
                          liveBottomInfo: liveBottomInfo,
                          overlayBadge: liveRecBadge,
                          onMinimize: _minimize,
                          onPrevious: _epIndex > 0
                              ? () => _playEpisodeAt(_epIndex - 1)
                              : null,
                          onNext:
                              (_epIndex >= 0 && _epIndex < _episodes.length - 1)
                                  ? () => _playEpisodeAt(_epIndex + 1)
                                  : null,
                        ),
                      ),
                    ),
                    // Slides + fades in with a slight pop instead of appearing
                    // abruptly, matching the animated chrome around it. Hidden
                    // in a PiP window (just the bare video floats there).
                    if (!_inPip)
                    Positioned(
                      right: 28,
                      bottom: 116,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                                    begin: const Offset(0, 0.4),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: _activeSkip == null
                            ? const SizedBox.shrink(key: ValueKey('no-skip'))
                            : FilledButton.icon(
                                key: ValueKey(_activeSkip!.isCredits
                                    ? 'credits'
                                    : 'intro'),
                                onPressed: () {
                                  final s = _activeSkip!;
                                  // Mark it skipped so an in-flight position
                                  // event can't flash the button back before
                                  // the seek lands; suppress the group echo.
                                  _autoSkipped.add(s.startTicks);
                                  _suppressGroup();
                                  _player.seek(s.end);
                                  setState(() => _activeSkip = null);
                                },
                                icon: const Icon(Icons.skip_next_rounded),
                                label: Text(_activeSkip!.isCredits
                                    ? l.playerSkipCredits
                                    : l.playerSkipIntro),
                              ),
                      ),
                    ),
                    // SyncPlay status cue (waiting/aligning, or SkipToSync).
                    if (!_inPip)
                      Positioned.fill(child: _SyncCueOverlay(cue: _syncCue)),
                    // Chromecast entry point (Android; hides itself where Cast is
                    // unavailable). Adapts the stream to the chosen target: a
                    // direct/HLS video for a TV, an HLS transcode for a speaker.
                    if (_isMobile && !_inPip)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 4,
                        right: 8,
                        child: CastButton(
                          resolve: _castMedia,
                          title: _title,
                          position: () => _player.state.position.inMilliseconds,
                          color: Colors.white,
                        ),
                      ),
                    // While a cast session is live (or connecting), local
                    // playback is paused and this covers the video so it's clear
                    // playback moved to the cast target, with a way to stop.
                    if (castStatus.casting && !_inPip)
                      Positioned.fill(
                        child: CastRemote(
                          artworkUrl: _castArtworkUrl(),
                          title: _castTitle(),
                          onPrevious: _epIndex > 0
                              ? () => _castEpisodeAt(_epIndex - 1)
                              : null,
                          onNext: (_epIndex >= 0 &&
                                  _epIndex < _episodes.length - 1)
                              ? () => _castEpisodeAt(_epIndex + 1)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _seekBy(int seconds) {
    final target = _player.state.position + Duration(seconds: seconds);
    final dur = _player.state.duration;
    _player.seek(target < Duration.zero
        ? Duration.zero
        : (target > dur ? dur : target));
  }

  /// Snap a live stream to the live edge, i.e. the end of whatever seekable
  /// window the server's transcode exposes.
  void _jumpToLive() {
    final dur = _player.state.duration;
    if (dur > Duration.zero) _safeSeek(dur);
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

  Map<ShortcutActivator, VoidCallback> _buildShortcuts(BuildContext context) {
    final keys = ref.read(preferencesProvider).asData?.value.effectiveKeys ??
        defaultKeyBindings();
    SingleActivator a(String id) =>
        SingleActivator(LogicalKeyboardKey(keys[id]!));
    return {
      // Fixed, always-on essentials.
      const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
          _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (isFullscreen(context)) toggleFullscreen(context);
      },
      // Customisable bindings.
      a('playPause'): _player.playOrPause,
      // Match the on-screen skip buttons (10 back / 30 forward), so the same
      // action isn't 10s by key and 30s by click.
      a('seekBackward'): () => _seekBy(-_kSeekBack),
      a('seekForward'): () => _seekBy(_kSeekForward),
      a('volumeUp'): () => _bumpVolume(5),
      a('volumeDown'): () => _bumpVolume(-5),
      a('mute'): _toggleMute,
      a('fullscreen'): () => toggleFullscreen(context),
    };
  }

  String get _title {
    final item = widget.item;
    if (!item.isEpisode) return item.name;
    final show = item.seriesName;
    final s = item.parentIndexNumber, e = item.indexNumber;
    final code = (s != null && e != null) ? 'S$s:E$e' : null;
    // e.g. "Rick and Morty · S6:E1 · Solaricks"
    return [
      if (show != null && show.isNotEmpty) show,
      ?code,
      item.name,
    ].join('  ·  ');
  }

  // Mirrors the default Jellyfin web client's quality list (bitrate in bps).
  static const _qualityOptions = <(int, String)>[
    (0, 'Auto'),
    (120000000, '4K - 120 Mbps'),
    (60000000, '1080p - 60 Mbps'),
    (40000000, '1080p - 40 Mbps'),
    (20000000, '1080p - 20 Mbps'),
    (15000000, '1080p - 15 Mbps'),
    (10000000, '1080p - 10 Mbps'),
    (8000000, '720p - 8 Mbps'),
    (6000000, '720p - 6 Mbps'),
    (4000000, '720p - 4 Mbps'),
    (3000000, '480p - 3 Mbps'),
    (1500000, '480p - 1.5 Mbps'),
    (720000, '480p - 720 kbps'),
    (420000, '360p - 420 kbps'),
  ];

  Future<void> _showQualityMenu() async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(l.playerQuality,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in _qualityOptions)
                      ListTile(
                        dense: true,
                        // Trailing checkmark, matching the subtitle/audio/speed
                        // sheets, instead of leading radio buttons.
                        title: Text(o.$2 == 'Auto' ? l.playerAuto : o.$2,
                            style: o.$1 == _qualityBitrate
                                ? TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary)
                                : null),
                        trailing: o.$1 == _qualityBitrate
                            ? Icon(Icons.check_rounded,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          _changeQuality(o.$1);
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

  Future<void> _showSubtitleMenu() {
    final l = AppLocalizations.of(context);
    return _pickFromSheet<SubtitleTrack>(
      title: l.playerSubtitles,
      options: _player.state.tracks.subtitle,
      isSelected: (t) => t.id == _player.state.track.subtitle.id,
      label: (t) => _subtitleLabel(l, t),
      onSelect: _player.setSubtitleTrack,
    );
  }

  Future<void> _showAudioMenu() {
    final l = AppLocalizations.of(context);
    return _pickFromSheet<AudioTrack>(
      title: l.playerAudio,
      options: _player.state.tracks.audio,
      isSelected: (t) => t.id == _player.state.track.audio.id,
      label: (t) => _audioLabel(l, t),
      onSelect: _player.setAudioTrack,
    );
  }

  Future<void> _showSpeedMenu() {
    final l = AppLocalizations.of(context);
    return _pickFromSheet<double>(
      title: l.playerPlaybackSpeed,
      options: const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
      isSelected: (s) => (s - _player.state.rate).abs() < 0.01,
      label: (s) => s == 1.0 ? l.playerSpeedNormal : '${s}x',
      onSelect: _player.setRate,
    );
  }

  Future<void> _showChapters() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(l.playerChapters,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < widget.item.chapters.length; i++)
                    ListTile(
                      title: Text(
                          widget.item.chapters[i].name?.isNotEmpty == true
                              ? widget.item.chapters[i].name!
                              : l.playerChapterNumbered(i + 1)),
                      trailing: Text(_fmtDur(widget.item.chapters[i].start)),
                      onTap: () {
                        _player.seek(widget.item.chapters[i].start);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _pickFromSheet<T>({
    required String title,
    required List<T> options,
    required bool Function(T) isSelected,
    required String Function(T) label,
    required void Function(T) onSelect,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(title,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      title: Text(label(o)),
                      trailing:
                          isSelected(o) ? const Icon(Icons.check_rounded) : null,
                      onTap: () {
                        onSelect(o);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _audioLabel(AppLocalizations l, AudioTrack t) {
    if (t.id == 'auto') return l.playerAuto;
    if (t.id == 'no') return l.playerNone;
    return _trackLabel(t.title, t.language) ?? l.playerTrackNumber(t.id);
  }

  static String _subtitleLabel(AppLocalizations l, SubtitleTrack t) {
    if (t.id == 'no') return l.commonOff;
    if (t.id == 'auto') return l.playerAuto;
    return _trackLabel(t.title, t.language) ?? l.playerSubtitleNumber(t.id);
  }

  static String? _trackLabel(String? title, String? language) {
    final parts = [title, language]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  const _ErrorOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white70, size: 48),
                const SizedBox(height: 16),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filledTonal(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single scrub-preview thumbnail cropped out of the server's trickplay tile
/// sheet for [positionMs], with a time caption beneath it.

/// The passive "REC" indicator shown while the live channel on screen is being
/// recorded. Watches [programRecordingProvider] so it appears and disappears as
/// timers are created or cancelled (here or from the guide). Renders nothing
/// when the current program has no timer.
class _LiveRecBadge extends ConsumerWidget {
  final String programId;
  const _LiveRecBadge({required this.programId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording =
        ref.watch(programRecordingProvider(programId)).asData?.value ?? false;
    if (!recording) return const SizedBox.shrink();
    return const _RecPill();
  }
}

/// A red "REC" pill with a pulsing dot.
class _RecPill extends StatefulWidget {
  const _RecPill();

  @override
  State<_RecPill> createState() => _RecPillState();
}

class _RecPillState extends State<_RecPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(AppLocalizations.of(context).playerBadgeRec,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

/// The SyncPlay status overlay, matching the official client: a pulsing
/// "syncing/waiting" glyph, or a brief SkipToSync flash (clock-forward to catch
/// up, clock-back to wait) framed by letterbox brackets.
class _SyncCueOverlay extends StatefulWidget {
  final String? cue; // 'sync' | 'fwd' | 'back' | null
  const _SyncCueOverlay({required this.cue});

  @override
  State<_SyncCueOverlay> createState() => _SyncCueOverlayState();
}

class _SyncCueOverlayState extends State<_SyncCueOverlay>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF00A4DC);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue = widget.cue;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: cue == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Center(key: ValueKey(cue), child: _glyph(cue)),
      ),
    );
  }

  Widget _glyph(String cue) {
    if (cue == 'sync') {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.08).animate(_pulse),
          child:
              _bubble(const Icon(Icons.sync_rounded, color: _teal, size: 46)),
        ),
      );
    }
    // Skip-to-sync: clock-forward (catch up) or clock-back (wait), bracketed.
    final icon = cue == 'fwd' ? Icons.update_rounded : Icons.history_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('[',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 46,
                height: 1,
                fontWeight: FontWeight.w200)),
        const SizedBox(width: 26),
        _bubble(Icon(icon, color: _teal, size: 48)),
        const SizedBox(width: 26),
        const Text(']',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 46,
                height: 1,
                fontWeight: FontWeight.w200)),
      ],
    );
  }

  Widget _bubble(Widget child) => Container(
        width: 92,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.38),
        ),
        child: child,
      );
}

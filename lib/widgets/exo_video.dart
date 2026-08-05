import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../api/jellyfin_client.dart';
import '../models/base_item.dart';
import 'trickplay_thumb.dart';

/// Live state pushed from the native ExoPlayer.
@immutable
class ExoState {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool playing;
  final bool buffering;
  final bool ended;
  final int width;
  final int height;
  // Playback-info details (see the native pushState). -1 / '' when unresolved.
  final String videoCodec;
  final double frameRate;
  final int videoBitrate;
  final String audioCodec;
  final int audioChannels;
  final int audioSampleRate;
  final int audioBitrate;
  final int droppedFrames;

  const ExoState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.playing = false,
    this.buffering = true,
    this.ended = false,
    this.width = 0,
    this.height = 0,
    this.videoCodec = '',
    this.frameRate = -1,
    this.videoBitrate = -1,
    this.audioCodec = '',
    this.audioChannels = -1,
    this.audioSampleRate = -1,
    this.audioBitrate = -1,
    this.droppedFrames = 0,
  });
}

/// One selectable audio or subtitle track, as reported by ExoPlayer.
@immutable
class ExoTrack {
  final int index;
  final String label;
  final String language;
  final bool selected;
  const ExoTrack({
    required this.index,
    required this.label,
    required this.language,
    required this.selected,
  });
}

/// Controls a single native Media3 ExoPlayer surface (see the Kotlin
/// `ExoVideoPlayer`). Created by the caller and handed to an [ExoVideo] widget,
/// which binds it to the platform view once Android creates it.
///
/// The native backend renders to a SurfaceView with hardware tunneling, so it
/// plays 4K / 10-bit HEVC HDR smoothly on low-power TV devices where the
/// texture/copy-back path drops frames.
class ExoVideoController {
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  final ValueNotifier<ExoState> state = ValueNotifier(const ExoState());
  final ValueNotifier<List<ExoTrack>> audioTracks = ValueNotifier(const []);
  final ValueNotifier<List<ExoTrack>> textTracks = ValueNotifier(const []);

  /// The active subtitle cue text (empty when none). We render video to a bare
  /// SurfaceView with no SubtitleView, so the native side forwards cues here and
  /// the Flutter player draws the overlay.
  final ValueNotifier<String> cues = ValueNotifier('');
  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  bool get isAttached => _method != null;

  /// Wired by [ExoVideo] when the platform view is created.
  void attach(int viewId) {
    _method = MethodChannel('app.fathom.player/exo_$viewId');
    _eventSub = EventChannel('app.fathom.player/exo_${viewId}_events')
        .receiveBroadcastStream()
        .listen(_onEvent);
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['event']) {
      case 'state':
        state.value = ExoState(
          position: Duration(milliseconds: (event['position'] as num).toInt()),
          duration: Duration(milliseconds: (event['duration'] as num).toInt()),
          buffered: Duration(milliseconds: (event['buffered'] as num).toInt()),
          playing: event['playing'] == true,
          buffering: event['buffering'] == true,
          ended: event['ended'] == true,
          width: (event['width'] as num?)?.toInt() ?? 0,
          height: (event['height'] as num?)?.toInt() ?? 0,
          videoCodec: '${event['videoCodec'] ?? ''}',
          frameRate: (event['frameRate'] as num?)?.toDouble() ?? -1,
          videoBitrate: (event['videoBitrate'] as num?)?.toInt() ?? -1,
          audioCodec: '${event['audioCodec'] ?? ''}',
          audioChannels: (event['audioChannels'] as num?)?.toInt() ?? -1,
          audioSampleRate: (event['audioSampleRate'] as num?)?.toInt() ?? -1,
          audioBitrate: (event['audioBitrate'] as num?)?.toInt() ?? -1,
          droppedFrames: (event['droppedFrames'] as num?)?.toInt() ?? 0,
        );
      case 'tracks':
        audioTracks.value = _parseTracks(event['audio']);
        textTracks.value = _parseTracks(event['text']);
      case 'cues':
        cues.value = '${event['text'] ?? ''}';
      case 'error':
        _errors.add('${event['message']}');
    }
  }

  List<ExoTrack> _parseTracks(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((t) {
      return ExoTrack(
        index: (t['index'] as num?)?.toInt() ?? 0,
        label: '${t['label'] ?? ''}',
        language: '${t['language'] ?? ''}',
        selected: t['selected'] == true,
      );
    }).toList();
  }

  /// [audioUrl] merges a separate audio-only track with a video-only [url] —
  /// how YouTube delivers anything above ~720p. Null for a self-contained
  /// (muxed / HLS / Jellyfin) stream.
  ///
  /// [subtitleUrl] sideloads a subtitle (YouTube captions arrive as a separate
  /// WebVTT URL). It's merged in and auto-shown; pass null to load with none.
  Future<void> load(String url,
          {String? audioUrl,
          String? subtitleUrl,
          String? subtitleLang,
          String? subtitleLabel,
          String? subtitleMime,
          Duration start = Duration.zero,
          bool play = true}) =>
      _method?.invokeMethod('load', {
        'url': url,
        if (audioUrl != null) 'audioUrl': audioUrl,
        if (subtitleUrl != null) 'subtitleUrl': subtitleUrl,
        if (subtitleLang != null) 'subtitleLang': subtitleLang,
        if (subtitleLabel != null) 'subtitleLabel': subtitleLabel,
        if (subtitleMime != null) 'subtitleMime': subtitleMime,
        'startPositionMs': start.inMilliseconds,
        'play': play,
      }) ??
      Future.value();

  Future<void> play() => _method?.invokeMethod('play') ?? Future.value();
  Future<void> pause() => _method?.invokeMethod('pause') ?? Future.value();
  Future<void> playOrPause() =>
      state.value.playing ? pause() : play();
  Future<void> seekTo(Duration position) =>
      _method?.invokeMethod('seekTo', {'positionMs': position.inMilliseconds}) ??
      Future.value();
  Future<void> setVolume(double volume) =>
      _method?.invokeMethod('setVolume', {'volume': volume.clamp(0, 1)}) ??
      Future.value();
  Future<void> setSpeed(double speed) =>
      _method?.invokeMethod('setSpeed', {'speed': speed}) ?? Future.value();
  Future<void> setAudioTrack(int index) =>
      _method?.invokeMethod('setAudioTrack', {'index': index}) ??
      Future.value();
  Future<void> setSubtitleTrack(int index) =>
      _method?.invokeMethod('setSubtitleTrack', {'index': index}) ??
      Future.value();

  /// The precise current position (native round-trip), for accurate seeks.
  Future<Duration> position() async {
    final ms = await _method?.invokeMethod<int>('position');
    return Duration(milliseconds: ms ?? state.value.position.inMilliseconds);
  }

  void dispose() {
    _method?.invokeMethod('dispose');
    _eventSub?.cancel();
    _errors.close();
    state.dispose();
    audioTracks.dispose();
    textTracks.dispose();
    cues.dispose();
  }
}

/// Embeds the native ExoPlayer SurfaceView in the Flutter tree. Fathom's own
/// controls are drawn on top by the caller (a Stack), so the whole player HUD
/// keeps working over the native surface.
///
/// Uses **Hybrid Composition** ([PlatformViewsService.initExpensiveAndroidView]):
/// a SurfaceView can't render into Flutter's default texture-layer path (it comes
/// out black), and hardware tunneling needs a real SurfaceView overlay, so hybrid
/// composition is mandatory here.
class ExoVideo extends StatelessWidget {
  const ExoVideo({
    super.key,
    required this.controller,
    this.tunneling = false,
  });

  final ExoVideoController controller;
  final bool tunneling;

  static const _viewType = 'app.fathom.player/exo_video';

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const {},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) {
        final avc = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: {'tunneling': tunneling},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        avc.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
        avc.addOnPlatformViewCreatedListener(controller.attach);
        avc.create();
        return avc;
      },
    );
  }
}

/// A seek bar for the ExoPlayer screens (Jellyfin + YouTube). On a TV the D-pad
/// focuses it and the player's root key handler scrubs (◀/▶) and leaves the bar
/// (▲/▼); it grows and gains a glowing thumb while focused so it reads as the
/// active control. On a phone/desktop it also takes touch: tap to seek, drag to
/// scrub. When the Jellyfin trickplay fields are supplied it shows a scrub-
/// preview thumbnail bubble above the bar (on hover or while dragging).
class ExoSeekBar extends StatefulWidget {
  const ExoSeekBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.markers = const [],
    this.client,
    this.baseUrl,
    this.itemId,
    this.trickplay,
    this.trickplayWidth,
    this.headers,
    this.showThumbnailPreview = true,
  });
  final ExoVideoController controller;
  final FocusNode focusNode;

  /// Positions to draw a thin tick at (chapter / segment starts). Empty draws
  /// none, so a plain seek bar is unchanged.
  final List<Duration> markers;

  /// Trickplay scrub-preview (Jellyfin VOD). All null on the YouTube path, which
  /// leaves the preview disabled and the bar otherwise unchanged.
  final JellyfinClient? client;
  final String? baseUrl;
  final String? itemId;
  final TrickplayInfo? trickplay;
  final int? trickplayWidth;
  final Map<String, String>? headers;
  final bool showThumbnailPreview;

  @override
  State<ExoSeekBar> createState() => _ExoSeekBarState();
}

class _ExoSeekBarState extends State<ExoSeekBar> {
  bool _focused = false;
  double? _dragFrac; // active touch-drag position (0..1)
  double? _previewFrac; // trickplay preview position (0..1)
  double? _previewX;

  void _seekToFrac(double frac) {
    final dur = widget.controller.state.value.duration;
    if (dur <= Duration.zero) return;
    widget.controller.seekTo(dur * frac.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _focused = v),
      child: ValueListenableBuilder<ExoState>(
        valueListenable: widget.controller.state,
        builder: (_, s, child) {
          final durMs = s.duration.inMilliseconds;
          final playedFrac = _dragFrac ??
              (durMs > 0
                  ? (s.position.inMilliseconds / durMs).clamp(0.0, 1.0)
                  : 0.0);
          final bufFrac = durMs > 0
              ? (s.buffered.inMilliseconds / durMs).clamp(0.0, 1.0)
              : 0.0;
          final info = widget.trickplay;
          final tWidth = widget.trickplayWidth;
          final base = widget.baseUrl;
          const double thumbH = 96;
          final double thumbW = (info != null && info.height > 0)
              ? thumbH * info.width / info.height
              : 160;
          final barH = _focused ? 8.0 : 5.0;
          return LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return MouseRegion(
                opaque: false,
                onHover: (e) {
                  if (info == null) return;
                  setState(() {
                    _previewX = e.localPosition.dx.clamp(0.0, w);
                    _previewFrac = (e.localPosition.dx / w).clamp(0.0, 1.0);
                  });
                },
                onExit: (_) {
                  if (_previewFrac != null && _dragFrac == null) {
                    setState(() {
                      _previewFrac = null;
                      _previewX = null;
                    });
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _seekToFrac(d.localPosition.dx / w),
                  onHorizontalDragStart: (d) {
                    final f = (d.localPosition.dx / w).clamp(0.0, 1.0);
                    setState(() {
                      _dragFrac = f;
                      _previewX = d.localPosition.dx.clamp(0.0, w);
                      _previewFrac = f;
                    });
                  },
                  onHorizontalDragUpdate: (d) {
                    final f = (d.localPosition.dx / w).clamp(0.0, 1.0);
                    setState(() {
                      _dragFrac = f;
                      _previewX = d.localPosition.dx.clamp(0.0, w);
                      _previewFrac = f;
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final f = _dragFrac;
                    if (f != null) _seekToFrac(f);
                    setState(() {
                      _dragFrac = null;
                      _previewFrac = null;
                      _previewX = null;
                    });
                  },
                  child: SizedBox(
                    height: 26,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        // Base track (fills the width).
                        Container(
                          height: barH,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Buffered.
                        Container(
                          width: w * bufFrac,
                          height: barH,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Played.
                        Container(
                          width: w * playedFrac,
                          height: barH,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Chapter / segment ticks. Skip the one at 0 (it sits
                        // under the left edge and just looks like a nick).
                        if (durMs > 0)
                          for (final m in widget.markers)
                            if (m.inMilliseconds > 0 &&
                                m.inMilliseconds < durMs)
                              Positioned(
                                left: (w * (m.inMilliseconds / durMs) - 1)
                                    .clamp(0.0, w - 2),
                                child: Container(
                                  width: 2,
                                  height: barH,
                                  color: Colors.white70,
                                ),
                              ),
                        // Handle: an enlarged glow while D-pad focused, a small
                        // dot while touch-dragging, nothing otherwise on TV.
                        if (_focused)
                          Positioned(
                            left: (w * playedFrac - 8).clamp(0.0, w - 16),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: scheme.primary
                                          .withValues(alpha: 0.7),
                                      blurRadius: 10)
                                ],
                              ),
                            ),
                          )
                        else if (_dragFrac != null)
                          Positioned(
                            left: (w * playedFrac - 7).clamp(0.0, w - 14),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 4,
                                      offset: Offset(0, 1)),
                                ],
                              ),
                            ),
                          ),
                        // Trickplay preview bubble (Jellyfin VOD only).
                        if (widget.showThumbnailPreview &&
                            info != null &&
                            tWidth != null &&
                            base != null &&
                            widget.client != null &&
                            widget.headers != null &&
                            widget.itemId != null &&
                            _previewFrac != null &&
                            _previewX != null &&
                            durMs > 0)
                          Positioned(
                            bottom: 26,
                            left: (_previewX! - thumbW / 2)
                                .clamp(-8.0, (w - thumbW + 8.0).clamp(-8.0, w)),
                            child: TrickplayThumb(
                              client: widget.client!,
                              baseUrl: base,
                              itemId: widget.itemId!,
                              info: info,
                              resolutionWidth: tWidth,
                              headers: widget.headers!,
                              positionMs:
                                  (s.duration * _previewFrac!).inMilliseconds,
                              thumbWidth: thumbW,
                              thumbHeight: thumbH,
                              label: fmtTime(s.duration * _previewFrac!),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

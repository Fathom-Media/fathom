import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import 'glass.dart';

class _TrickplayThumb extends StatelessWidget {
  final JellyfinClient client;
  final String baseUrl;
  final String itemId;
  final TrickplayInfo info;
  final int resolutionWidth;
  final Map<String, String> headers;
  final int positionMs;
  final double thumbWidth;
  final double thumbHeight;
  final String label;

  const _TrickplayThumb({
    required this.client,
    required this.baseUrl,
    required this.itemId,
    required this.info,
    required this.resolutionWidth,
    required this.headers,
    required this.positionMs,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final maxN = info.thumbnailCount > 0 ? info.thumbnailCount - 1 : 0;
    final n = (positionMs ~/ (info.interval > 0 ? info.interval : 10000))
        .clamp(0, maxN);
    final perTile = info.perTile > 0 ? info.perTile : 1;
    final tileIndex = n ~/ perTile;
    final within = n % perTile;
    final row = within ~/ info.tileWidth;
    final col = within % info.tileWidth;

    final dispH = thumbHeight;
    final dispW = thumbWidth;
    final url = client.trickplayTileUrl(
      baseUrl: baseUrl,
      itemId: itemId,
      width: resolutionWidth,
      tileIndex: tileIndex,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: dispW,
            height: dispH,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(-col * dispW, -row * dispH),
                child: Image.network(
                  url,
                  width: dispW * info.tileWidth,
                  height: dispH * info.tileHeight,
                  fit: BoxFit.fill,
                  headers: headers,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

String _fmtTime(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  final s = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  return neg ? '-$s' : s;
}

/// Fathom's own auto-hiding player chrome: a cinematic top bar, a centered
/// transport with 10s-back / 30s-forward skips, and a bottom bar with a custom
/// seek bar (trickplay preview), track pickers, volume and fullscreen.
/// A tick on the seek bar: a chapter start, an intro, a credits roll.
///
/// Deliberately generic. This bar is hand-written precisely because media_kit's
/// built-in one has no marker API, and both players want ticks for different
/// reasons — YouTube chapters here, Jellyfin chapters and media segments there.
typedef PlayerMarker = ({Duration position, String label});

/// Material only ships numbered replay/forward icons for 5, 10 and 30. For any
/// other interval the plain arrows are used rather than an icon that states a
/// number the button doesn't do.
IconData _replayIcon(int seconds) => switch (seconds) {
      5 => Icons.replay_5_rounded,
      10 => Icons.replay_10_rounded,
      30 => Icons.replay_30_rounded,
      _ => Icons.fast_rewind_rounded,
    };

IconData _forwardIcon(int seconds) => switch (seconds) {
      5 => Icons.forward_5_rounded,
      10 => Icons.forward_10_rounded,
      30 => Icons.forward_30_rounded,
      _ => Icons.fast_forward_rounded,
    };

class FathomPlayerControls extends StatefulWidget {
  final Player player;
  final String? trickItemId;
  final String title;

  /// Live channel number, shown as a small pill beside the channel name in the
  /// top bar. Null/empty hides it.
  final String? channelNumber;
  final bool isLive;
  final bool loading;
  final VoidCallback onBack;
  final void Function(int seconds) onSeekBy;

  /// Jumps a live stream to the live edge. Powers the LIVE button; null for VOD.
  final VoidCallback? onJumpToLive;
  final VoidCallback? onSubtitles;
  final VoidCallback? onAudio;
  final VoidCallback? onSpeed;
  final VoidCallback? onQuality;
  final String qualityLabel;
  final VoidCallback? onChapters;

  /// Live TV record control. Lives in the bottom bar with the other actions,
  /// not floating in the title bar.
  final Widget? recordButton;
  final VoidCallback onToggleMute;
  final TrickplayInfo? trickplay;
  final int? trickplayWidth;

  /// Ticks drawn on the seek bar. Empty draws none.
  final List<PlayerMarker> markers;

  /// How far the skip buttons jump. Defaulted to the industry-standard 10/30,
  /// which is what the Jellyfin player uses; only the YouTube player overrides
  /// them, from its own settings. These controls are shared, so a setting
  /// applied in here would reach across to Jellyfin.
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final String? baseUrl;
  final JellyfinClient? client;
  final Map<String, String>? headers;

  /// Full-screen players hide their chrome after a few seconds of stillness.
  /// An embedded player (the watch page) keeps it up: the pointer spends most
  /// of its time outside the video, so there'd be no way to reach pause.
  final bool autoHide;

  /// Control-bar chrome, chosen in Player settings and passed in by the caller
  /// (the shared controls never read prefs themselves): 'none' | 'glass' | 'dark'.
  final String barStyle;

  /// Hides the top bar (title + back) when the surrounding page already shows
  /// that context.
  final bool showTopBar;

  /// Whether to offer a fullscreen toggle (the bar button and the double-tap-
  /// centre gesture). Off on a phone, where the player route already fills the
  /// screen and orientation handles the rest, so media_kit's own fullscreen
  /// doesn't fight the forced-landscape lock.
  final bool showFullscreen;

  /// Enables the phone swipe gestures: vertical drag on the left half changes
  /// screen brightness, on the right half changes volume (each with a HUD).
  /// Off on desktop, where there's no touch and no per-app brightness.
  final bool touchGestures;

  /// Minimizes the video into the floating mini player. Null hides the button.
  final VoidCallback? onMinimize;

  /// Toggles theater mode (a wider in-page player with the side rail hidden).
  /// Null hides the button; shown only outside fullscreen, like YouTube.
  final VoidCallback? onToggleTheater;

  /// Whether theater mode is currently on (tints the theater button).
  final bool theaterActive;

  /// Advances to the next video/episode. Null hides the Next button.
  final VoidCallback? onNext;

  /// Goes to the previous episode. Null hides the Previous button (only the
  /// Jellyfin episode player provides it).
  final VoidCallback? onPrevious;

  /// Whether to show the hover scrub-preview thumbnail (user setting). Governs
  /// both the Jellyfin trickplay bubble and the YouTube storyboard bubble.
  final bool showThumbnailPreview;

  /// A rich "now playing" panel (live TV channel/show/description), shown
  /// lower-left and fading with the controls. Rendered inside the chrome, so it
  /// appears in fullscreen too. Null for non-live content.
  final Widget? infoPanel;

  /// Live TV program block (show title, description, program timeline with a
  /// LIVE edge) rendered inside the frosted bottom bar, in place of the
  /// meaningless live-buffer scrubber. Null for non-live content.
  final Widget? liveBottomInfo;

  /// A badge shown top-right (e.g. the live REC indicator). Rendered inside the
  /// chrome, so it fades in and out with the rest of the controls and appears in
  /// fullscreen too. Null hides it.
  final Widget? overlayBadge;

  const FathomPlayerControls({
    super.key,
    required this.player,
    this.trickItemId,
    required this.title,
    this.channelNumber,
    required this.isLive,
    required this.loading,
    required this.onBack,
    required this.onSeekBy,
    this.onJumpToLive,
    required this.onToggleMute,
    this.autoHide = true,
    this.barStyle = 'glass',
    this.showTopBar = true,
    this.showFullscreen = true,
    this.touchGestures = false,
    this.onMinimize,
    this.onToggleTheater,
    this.theaterActive = false,
    this.onNext,
    this.onPrevious,
    this.onSubtitles,
    this.onAudio,
    this.onSpeed,
    this.onQuality,
    this.qualityLabel = '',
    this.onChapters,
    this.recordButton,
    this.trickplay,
    this.trickplayWidth,
    this.markers = const [],
    this.seekBackSeconds = 10,
    this.seekForwardSeconds = 30,
    this.baseUrl,
    this.client,
    this.headers,
    this.showThumbnailPreview = true,
    this.infoPanel,
    this.liveBottomInfo,
    this.overlayBadge,
  });

  @override
  State<FathomPlayerControls> createState() => _FathomPlayerControlsState();
}

class _FathomPlayerControlsState extends State<FathomPlayerControls>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  bool _playing = true;
  Timer? _hideTimer;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<double>? _volSub;

  // A translucent play/pause silhouette flashed in the centre when the picture
  // is clicked to toggle playback (the only feedback the video itself needs).
  late final AnimationController _flashCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  IconData? _flashIcon;

  // A transient top-centre HUD flashed on volume change or a double-click seek,
  // so those actions give feedback even when the chrome is hidden.
  bool _hudVisible = false;
  IconData? _hudIcon;
  String _hudText = '';
  Timer? _hudTimer;
  double _lastVolume = 0;

  // Current per-app screen brightness (0..1), seeded from the OS on first drag.
  // Only touched on mobile, where [widget.touchGestures] is on.
  double? _brightness;
  bool _brightnessChanged = false;

  Player get _p => widget.player;

  @override
  void initState() {
    super.initState();
    _playing = _p.state.playing;
    _lastVolume = _p.state.volume;
    if (widget.touchGestures) {
      ScreenBrightness()
          .application
          .then((b) => _brightness = b)
          .catchError((_) => _brightness = 0.5);
    }
    _playSub = _p.stream.playing.listen((v) {
      if (!mounted) return;
      _playing = v;
      if (!v) {
        // Paused: keep the chrome up so the user can see where they are.
        _hideTimer?.cancel();
        if (!_visible) setState(() => _visible = true);
      } else {
        _scheduleHide();
      }
    });
    _volSub = _p.stream.volume.listen((v) {
      // Flash only on a real change. _lastVolume is seeded from the current
      // volume in initState, so the magnitude gate alone handles the initial
      // value without swallowing the user's first real change.
      if (!mounted || (v - _lastVolume).abs() < 0.5) return;
      _lastVolume = v;
      final icon = v <= 0
          ? Icons.volume_off_rounded
          : (v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
      _flashHud(icon, '${v.round()}%');
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _flashCtrl.dispose();
    _playSub?.cancel();
    _volSub?.cancel();
    // Hand brightness back to the system so a manual level doesn't stick after
    // leaving the player.
    if (_brightnessChanged) {
      ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    }
    super.dispose();
  }

  /// Vertical drag on the left half: screen brightness. [dy] is the per-event
  /// delta in logical pixels (positive = downward = dimmer).
  void _dragBrightness(double dy) {
    final next = ((_brightness ?? 0.5) - dy * 0.003).clamp(0.0, 1.0);
    _brightness = next;
    _brightnessChanged = true;
    ScreenBrightness()
        .setApplicationScreenBrightness(next)
        .catchError((_) {});
    _flashHud(
      next < 0.34
          ? Icons.brightness_low_rounded
          : (next < 0.67
              ? Icons.brightness_medium_rounded
              : Icons.brightness_high_rounded),
      '${(next * 100).round()}%',
    );
    _show();
  }

  /// Vertical drag on the right half: playback volume (positive dy = quieter).
  void _dragVolume(double dy) {
    final next = (_p.state.volume - dy * 0.35).clamp(0.0, 100.0);
    _p.setVolume(next);
    _lastVolume = next;
    _flashHud(
      next <= 0
          ? Icons.volume_off_rounded
          : (next < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
      '${next.round()}%',
    );
    _show();
  }

  void _flashHud(IconData icon, String text) {
    if (!mounted) return;
    setState(() {
      _hudIcon = icon;
      _hudText = text;
      _hudVisible = true;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  /// Double-click-a-side seek, with a flashed HUD. Negative seconds = back.
  void _seekZone(int seconds) {
    widget.onSeekBy(seconds);
    _flashHud(
      seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
      '${seconds > 0 ? '+' : ''}${seconds}s',
    );
    _show();
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.autoHide) return;
    // Only while playing: a paused video keeps its controls up, because
    // "paused" is exactly when you want the transport in reach.
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _visible = false);
    });
  }

  /// Clicking the picture plays or pauses, as it does in every other player.
  ///
  /// It used to mean "toggle the chrome" whenever the chrome auto-hid, so the
  /// same click did different things depending on where the player was
  /// embedded. There's nothing to reveal by clicking anyway: moving the pointer
  /// already brings the chrome back, and it takes itself away again.
  void _toggle() {
    // Flash the icon of the action taken: pausing shows pause, resuming play.
    _flashIcon = _playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
    _flashCtrl.forward(from: 0);
    _p.playOrPause();
    _show();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return MouseRegion(
      // Only blank the pointer once the chrome has actually hidden itself.
      cursor: (_visible || !widget.autoHide)
          ? MouseCursor.defer
          : SystemMouseCursors.none,
      onHover: (_) => _show(),
      child: Stack(
        children: [
          // Tap surface, behind the chrome. Single tap anywhere plays/pauses;
          // double-tap the left/right third seeks (with a HUD), the centre third
          // toggles fullscreen. Live has no seek, so its sides fall back to
          // fullscreen too.
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onDoubleTap: widget.isLive
                        ? (widget.showFullscreen
                            ? () => toggleFullscreen(context)
                            : null)
                        : () => _seekZone(-widget.seekBackSeconds),
                    onVerticalDragUpdate: widget.touchGestures
                        ? (d) => _dragBrightness(d.primaryDelta ?? 0)
                        : null,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onDoubleTap: widget.showFullscreen
                        ? () => toggleFullscreen(context)
                        : null,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onDoubleTap: widget.isLive
                        ? (widget.showFullscreen
                            ? () => toggleFullscreen(context)
                            : null)
                        : () => _seekZone(widget.seekForwardSeconds),
                    onVerticalDragUpdate: widget.touchGestures
                        ? (d) => _dragVolume(d.primaryDelta ?? 0)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (widget.loading)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(widget.isLive ? l.playerTuningIn : l.playerLoading,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _chrome(context),
              ),
            ),
          ),
          // Transient volume/seek HUD, above the chrome so it shows even when
          // the controls are hidden.
          Positioned(
            top: 28,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _hudVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _HudChip(icon: _hudIcon, text: _hudText),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        // Live "now playing" panel, lower-left above the transport. Ignores
        // pointers so a tap in its area still falls through to play/pause.
        if (widget.infoPanel != null)
          Positioned(
              left: 24,
              bottom: 104,
              child: IgnorePointer(child: widget.infoPanel!)),
        // Top-right badge (e.g. REC), fading with the rest of the chrome.
        if (widget.overlayBadge != null)
          Positioned(
              top: 14, right: 16, child: IgnorePointer(child: widget.overlayBadge!)),
        // Top scrim + title bar.
        if (widget.showTopBar)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.only(bottom: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.62), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 0),
                child: Row(
                  children: [
                    _AnimatedIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l.commonBack,
                      onTap: widget.onBack,
                    ),
                    const SizedBox(width: 6),
                    if ((widget.channelNumber ?? '').isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.channelNumber!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // A translucent play/pause silhouette that scales up and fades when the
        // picture is clicked. The transport itself lives in the bottom bar now,
        // so nothing is parked over the middle of the video.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _flashCtrl,
                builder: (context, _) {
                  final t = _flashCtrl.value;
                  if (t == 0 || t == 1 || _flashIcon == null) {
                    return const SizedBox.shrink();
                  }
                  return Opacity(
                    opacity: (1 - t) * 0.9,
                    child: Transform.scale(
                      scale: 0.7 + 0.6 * t,
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                        child: Icon(_flashIcon, size: 54, color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Bottom scrim + seek bar + controls.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomChrome(
            isLive: widget.isLive,
            style: widget.barStyle,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Live TV: the program info block (title, air window,
                  // description) sits above the transport in the frosted bar.
                  if (widget.liveBottomInfo != null) ...[
                    widget.liveBottomInfo!,
                    const SizedBox(height: 12),
                  ],
                  // Transport bar: position, seek bar, and (for live) a LIVE
                  // button in place of the trailing remaining time.
                  Row(
                    children: [
                      _PositionText(player: _p, remaining: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FathomSeekBar(
                          player: _p,
                          accent: accent,
                          onInteract: _show,
                          trickplay: widget.isLive ? null : widget.trickplay,
                          trickplayWidth:
                              widget.isLive ? null : widget.trickplayWidth,
                          markers: widget.isLive ? const [] : widget.markers,
                          baseUrl: widget.baseUrl,
                          itemId: widget.trickItemId ?? '',
                          client: widget.client,
                          headers: widget.headers,
                          showThumbnailPreview: widget.isLive
                              ? false
                              : widget.showThumbnailPreview,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (widget.isLive)
                        _LiveButton(
                          player: _p,
                          onJumpToLive: widget.onJumpToLive,
                          onInteract: _show,
                        )
                      else
                        _PositionText(player: _p, remaining: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // The bar carries up to eight controls plus a 90px volume
                  // slider — about 470px of fixed width with only a Spacer
                  // between them. A Spacer cannot shrink below zero, so in a
                  // narrow window the Row overflowed and painted the striped
                  // overflow warning. Shed the slider first, then fold the
                  // optional controls into a menu, so it fits at any width.
                  LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth;
                    final compactVolume = w < 560;
                    final folded = w < 460;

                    // Convention over balance: Volume anchors the LEFT (where
                    // every player puts it), and the track/stream pickers
                    // (Subtitles, Audio, Quality) + playback nav (Chapters,
                    // Speed) cluster on the RIGHT beside Theater/Fullscreen,
                    // where settings-style controls live. Matches YouTube/VLC
                    // muscle memory rather than evening out the bar for its own
                    // sake.
                    final tracks = <(IconData, String, VoidCallback)>[
                      if (widget.onSubtitles != null)
                        (
                          Icons.closed_caption_rounded,
                          l.playerSubtitles,
                          widget.onSubtitles!
                        ),
                      if (widget.onAudio != null)
                        (
                          Icons.multitrack_audio_rounded,
                          l.playerAudio,
                          widget.onAudio!
                        ),
                      if (widget.onQuality != null)
                        (
                          Icons.high_quality_rounded,
                          l.playerQualityLabel(widget.qualityLabel),
                          widget.onQuality!
                        ),
                    ];
                    final nav = <(IconData, String, VoidCallback)>[
                      if (widget.onChapters != null)
                        // A numbered-list glyph reads as chapters; the old
                        // generic list icon was the bar's least legible.
                        (Icons.format_list_numbered_rounded, l.playerChapters,
                            widget.onChapters!),
                      if (widget.onSpeed != null)
                        (Icons.speed_rounded, l.playerPlaybackSpeed,
                            widget.onSpeed!),
                    ];
                    final optional = [...tracks, ...nav];

                    if (folded) {
                      return Row(
                        children: [
                          // Play/pause + Volume on the left; the skip circles
                          // fold away on a narrow bar (double-tap the sides still
                          // seeks). Next joins the right group.
                          ?widget.recordButton,
                          _BarPlayPause(
                              player: _p,
                              onTap: () {
                                _p.playOrPause();
                                _show();
                              }),
                          _VolumeControl(
                            player: _p,
                            accent: accent,
                            onToggleMute: widget.onToggleMute,
                            onInteract: _show,
                            compact: true,
                          ),
                          const Spacer(),
                          if (widget.onPrevious != null)
                            _BarButton(
                                icon: Icons.skip_previous_rounded,
                                tooltip: l.commonPrevious,
                                onTap: () {
                                  widget.onPrevious!();
                                  _show();
                                }),
                          if (widget.onNext != null)
                            _BarButton(
                                icon: Icons.skip_next_rounded,
                                tooltip: l.commonNext,
                                onTap: () {
                                  widget.onNext!();
                                  _show();
                                }),
                          if (optional.isNotEmpty)
                            PopupMenuButton<VoidCallback>(
                              tooltip: l.playerMore,
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: Colors.white, size: 22),
                              onSelected: (fn) {
                                fn();
                                _show();
                              },
                              itemBuilder: (_) => [
                                for (final o in optional)
                                  PopupMenuItem(
                                    value: o.$3,
                                    child: Row(children: [
                                      Icon(o.$1, size: 18),
                                      const SizedBox(width: 12),
                                      Text(o.$2),
                                    ]),
                                  ),
                              ],
                            ),
                          // Theater mode is a non-fullscreen concept, so the
                          // button hides in fullscreen, like YouTube.
                          if (widget.onToggleTheater != null &&
                              !isFullscreen(context))
                            _TheaterButton(
                                active: widget.theaterActive,
                                onTap: widget.onToggleTheater!,
                                onInteract: _show),
                          // No picture-in-picture while fullscreen: minimizing
                          // there would hand the player to the dock from behind
                          // the fullscreen route and strand it. Exit fullscreen
                          // first, as the YouTube player does.
                          if (widget.onMinimize != null &&
                              !isFullscreen(context))
                            _MinimizeButton(
                                onMinimize: widget.onMinimize!,
                                onInteract: _show),
                          if (widget.showFullscreen)
                            _FullscreenButton(onInteract: _show),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        // Left transport: play/pause, then the skip back/forward
                        // circles, then Volume. Record leads it for live.
                        ?widget.recordButton,
                        _BarPlayPause(
                            player: _p,
                            onTap: () {
                              _p.playOrPause();
                              _show();
                            }),
                        if (!widget.isLive) ...[
                          _CircleTransport(
                            icon: _replayIcon(widget.seekBackSeconds),
                            size: 22,
                            spinForward: false,
                            onTap: () {
                              widget.onSeekBy(-widget.seekBackSeconds);
                              _show();
                            },
                          ),
                          _CircleTransport(
                            icon: _forwardIcon(widget.seekForwardSeconds),
                            size: 22,
                            spinForward: true,
                            onTap: () {
                              widget.onSeekBy(widget.seekForwardSeconds);
                              _show();
                            },
                          ),
                        ],
                        _VolumeControl(
                          player: _p,
                          accent: accent,
                          onToggleMute: widget.onToggleMute,
                          onInteract: _show,
                          compact: compactVolume,
                        ),
                        const Spacer(),
                        // Right cluster: Previous/Next lead it, then the
                        // track/nav pickers and view controls.
                        if (widget.onPrevious != null)
                          _BarButton(
                              icon: Icons.skip_previous_rounded,
                              tooltip: l.commonPrevious,
                              onTap: () {
                                widget.onPrevious!();
                                _show();
                              }),
                        if (widget.onNext != null)
                          _BarButton(
                              icon: Icons.skip_next_rounded,
                              tooltip: l.commonNext,
                              onTap: () {
                                widget.onNext!();
                                _show();
                              }),
                        for (final o in [...tracks, ...nav])
                          _BarButton(icon: o.$1, tooltip: o.$2, onTap: o.$3),
                        // Theater mode is a non-fullscreen concept, so the
                        // button hides in fullscreen, like YouTube.
                        if (widget.onToggleTheater != null &&
                            !isFullscreen(context))
                          _TheaterButton(
                              active: widget.theaterActive,
                              onTap: widget.onToggleTheater!,
                              onInteract: _show),
                        // Hidden while fullscreen (see the folded branch above).
                        if (widget.onMinimize != null && !isFullscreen(context))
                          _MinimizeButton(
                              onMinimize: widget.onMinimize!,
                              onInteract: _show),
                        if (widget.showFullscreen)
                          _FullscreenButton(onInteract: _show),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bottom control-bar background. The user picks the chrome from Player
/// settings (playerBarStyle), and the caller passes it in as [style]:
///  - 'none'  a plain darkening gradient, no blur (lightest on the GPU);
///  - 'glass' a subdued frosted panel (blurred, translucent, hairline top edge);
///  - 'dark'  a heavier, darker frosted panel.
/// For 'glass'/'dark', VOD/YouTube also lay a soft wash over the glass so the
/// position text and hovering trickplay thumbnail stay readable against bright
/// video; live has no seek preview, so it keeps the cleaner glass alone.
class _BottomChrome extends StatelessWidget {
  final bool isLive;

  /// Chrome style, passed in by the caller (not read from prefs here, so the
  /// shared controls stay settings-agnostic): 'none' | 'glass' | 'dark'.
  final String style;
  final Widget child;
  const _BottomChrome(
      {required this.isLive, required this.style, required this.child});

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: EdgeInsets.fromLTRB(18, style == 'none' ? 30 : 14, 18, 8),
      child: child,
    );

    // No glass: just a darkening gradient behind the controls, no BackdropFilter.
    if (style == 'none') {
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.82),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          padded,
        ],
      );
    }

    final dark = style == 'dark';
    // The frosted glass is a BACKGROUND layer, not a wrapper: the interactive
    // controls (and their fullscreen inherited dependency) must NOT be
    // descendants of the BackdropFilter. media_kit reparents the video subtree
    // on a fullscreen toggle, and descending the fullscreen-dependent controls
    // under a blur that gets reparented broke fullscreen and asserted on
    // teardown ("_dependents.isEmpty"). Keeping the blur as a sibling behind the
    // content mirrors the isolated BackdropFilter the info card used.
    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface(
            blur: dark ? 13 : 7,
            color: Colors.black.withValues(alpha: dark ? 0.40 : 0.18),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: dark ? 0.10 : 0.06)),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        // Readability wash for VOD/YouTube (trickplay + times over the picture).
        if (!isLive)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: dark ? 0.20 : 0.26),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        padded,
      ],
    );
  }
}

/// The live-edge button. It lights solid red when you're at (or near) the live
/// edge, and shows a tappable outline when you've scrubbed behind live; tapping
/// snaps back to the edge. Whether there's any room to be "behind" at all is
/// governed entirely by the player's seekable range, i.e. the server's buffer.
class _LiveButton extends StatelessWidget {
  final Player player;
  final VoidCallback? onJumpToLive;
  final VoidCallback onInteract;
  const _LiveButton({
    required this.player,
    required this.onInteract,
    this.onJumpToLive,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const red = Color(0xFFE53935);
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final dur = player.state.duration;
        // "At live" when within a few seconds of the seekable edge, or when the
        // stream exposes no rewindable window at all.
        final atLive = dur <= Duration.zero ||
            (dur - pos) <= const Duration(seconds: 10);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: atLive
              ? null
              : () {
                  onJumpToLive?.call();
                  onInteract();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: atLive ? red : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color:
                      atLive ? red : Colors.white.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle,
                    size: 7,
                    color: atLive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6)),
                const SizedBox(width: 5),
                Text(l.playerBadgeLive,
                    style: TextStyle(
                        color: atLive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A round transport button (skip back/forward) whose icon spins a full turn on
/// each tap, in the direction of the skip, so the seek is felt as well as seen.
class _CircleTransport extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  /// Clockwise for a forward skip, counter-clockwise for a rewind.
  final bool spinForward;
  const _CircleTransport(
      {required this.icon,
      required this.size,
      required this.onTap,
      required this.spinForward});

  @override
  State<_CircleTransport> createState() => _CircleTransportState();
}

class _CircleTransportState extends State<_CircleTransport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turns = Tween<double>(begin: 0, end: widget.spinForward ? 1 : -1)
        .animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic));
    return _AnimatedControl(
      onTap: () {
        _spin.forward(from: 0);
        widget.onTap();
      },
      // No resting circle: just the icon, matching the other bar controls (only
      // a hover halo appears, like them).
      child: RotationTransition(
        turns: turns,
        // Inherits the hover accent tint from _AnimatedControl.
        child: Icon(widget.icon, size: widget.size),
      ),
    );
  }
}

class _PositionText extends StatelessWidget {
  final Player player;
  final bool remaining; // false = elapsed, true = -remaining
  const _PositionText({required this.player, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = player.state.duration;
        final value = remaining ? pos - dur : pos;
        return Text(
          dur <= Duration.zero && remaining ? '--:--' : _fmtTime(value),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w500),
        );
      },
    );
  }
}

/// The shared player-control button: grows on hover (no circular highlight or
/// halo), and springs inward on press. Every transport and bar control uses it
/// so hover and click feel alive rather than static.
class _AnimatedControl extends StatefulWidget {
  final Widget child;
  final String? tooltip;
  final VoidCallback onTap;
  const _AnimatedControl({
    required this.child,
    required this.onTap,
    this.tooltip,
  });

  @override
  State<_AnimatedControl> createState() => _AnimatedControlState();
}

class _AnimatedControlState extends State<_AnimatedControl> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Press wins over hover, so a click reads as a deliberate inward press even
    // while the pointer is over the button.
    final scale = _pressed ? 0.88 : (_hover ? 1.16 : 1.0);

    Widget child = AnimatedScale(
      scale: scale,
      // easeOutBack overshoots slightly, so the button springs rather than
      // glides; a shorter press duration makes the click feel snappy.
      duration: Duration(milliseconds: _pressed ? 90 : 240),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      // Padding keeps the tap target comfortably larger than the glyph.
      child: Padding(
        padding: const EdgeInsets.all(8),
        // Icons that don't set their own colour inherit this, so a plain white
        // control warms to the accent on hover; genuine state colours (theater
        // active, live) set an explicit colour and are left untouched.
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          tween: ColorTween(
              begin: Colors.white, end: _hover ? accent : Colors.white),
          builder: (context, color, ch) => IconTheme.merge(
            data: IconThemeData(color: color),
            child: ch!,
          ),
          child: widget.child,
        ),
      ),
    );

    child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: child,
      ),
    );

    final tip = widget.tooltip;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}

/// A plain 22px-icon bar control: [_AnimatedControl] with an [Icon] child. The
/// hero buttons (play/pause morph, spinning skips) pass their own animated child
/// to [_AnimatedControl] directly.
class _AnimatedIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;

  const _AnimatedIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return _AnimatedControl(
      onTap: onTap,
      tooltip: tooltip,
      // No explicit colour: inherits _AnimatedControl's IconTheme (white, or
      // accent on hover).
      child: Icon(icon, size: 22),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _BarButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _AnimatedIconButton(icon: icon, tooltip: tooltip, onTap: onTap);
  }
}

/// A compact play/pause for the bottom bar; tracks the player's own state so its
/// icon flips whether the toggle came from here, the centre tap, or a hotkey.
class _BarPlayPause extends StatefulWidget {
  final Player player;
  final VoidCallback onTap;
  const _BarPlayPause({required this.player, required this.onTap});

  @override
  State<_BarPlayPause> createState() => _BarPlayPauseState();
}

class _BarPlayPauseState extends State<_BarPlayPause> {
  late bool _playing = widget.player.state.playing;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.stream.playing.listen((v) {
      if (mounted && v != _playing) setState(() => _playing = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _BarButton(
      icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      tooltip: _playing ? l.commonPause : l.commonPlay,
      onTap: widget.onTap,
    );
  }
}

class _VolumeControl extends StatelessWidget {
  final Player player;
  final Color accent;
  final VoidCallback onToggleMute;
  final VoidCallback onInteract;

  /// Drops the 90px slider and keeps just the mute toggle. The bar runs out of
  /// room before the video does, and a slider is the first thing worth losing.
  final bool compact;

  const _VolumeControl(
      {required this.player,
      required this.accent,
      required this.onToggleMute,
      required this.onInteract,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (_, snap) {
        final vol = snap.data ?? 100;
        final icon = vol <= 0
            ? Icons.volume_off_rounded
            : (vol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedIconButton(
              tooltip: l.playerMute,
              icon: icon,
              onTap: () {
                onToggleMute();
                onInteract();
              },
            ),
            if (!compact)
              SizedBox(
              width: 90,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: vol.clamp(0, 100),
                  max: 100,
                  onChanged: (v) {
                    player.setVolume(v);
                    onInteract();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The transient volume/seek feedback pill.
class _HudChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  const _HudChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _MinimizeButton extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback onInteract;
  const _MinimizeButton({required this.onMinimize, required this.onInteract});

  @override
  Widget build(BuildContext context) {
    return _AnimatedIconButton(
      tooltip: AppLocalizations.of(context).playerMiniplayer,
      icon: Icons.picture_in_picture_alt_rounded,
      onTap: () {
        onMinimize();
        onInteract();
      },
    );
  }
}

/// Theater-mode toggle (YouTube's wide-player-without-rail view). Tints to the
/// accent colour while active.
class _TheaterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onInteract;
  const _TheaterButton({
    required this.active,
    required this.onTap,
    required this.onInteract,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return _AnimatedControl(
      tooltip: active ? l.playerDefaultView : l.playerTheaterMode,
      onTap: () {
        onTap();
        onInteract();
      },
      // A wide screen glyph to go theater, a narrower one to come back, like
      // YouTube's two-state button; accent while active, otherwise inherits the
      // hover tint from _AnimatedControl (null = white at rest, accent on hover).
      child: Icon(
          active ? Icons.crop_7_5_rounded : Icons.crop_landscape_rounded,
          size: 22,
          color: active ? accent : null),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  final VoidCallback onInteract;
  const _FullscreenButton({required this.onInteract});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final full = isFullscreen(context);
    return _AnimatedIconButton(
      tooltip: full ? l.playerExitFullscreen : l.playerFullscreen,
      icon: full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      onTap: () {
        toggleFullscreen(context);
        onInteract();
      },
    );
  }
}

/// Custom seek bar with a buffered underlay, a draggable thumb, and a
/// trickplay scrub-preview bubble that follows the cursor on hover.
class _FathomSeekBar extends StatefulWidget {
  final Player player;
  final Color accent;
  final VoidCallback onInteract;
  final TrickplayInfo? trickplay;
  final int? trickplayWidth;
  final String? baseUrl;
  final String itemId;
  final JellyfinClient? client;
  final Map<String, String>? headers;
  final List<PlayerMarker> markers;

  /// When false, the hover scrub-preview bubble is suppressed (user setting).
  final bool showThumbnailPreview;

  const _FathomSeekBar({
    required this.player,
    required this.accent,
    required this.onInteract,
    required this.trickplay,
    required this.trickplayWidth,
    required this.baseUrl,
    required this.itemId,
    required this.client,
    required this.headers,
    this.markers = const [],
    this.showThumbnailPreview = true,
  });

  @override
  State<_FathomSeekBar> createState() => _FathomSeekBarState();
}

class _FathomSeekBarState extends State<_FathomSeekBar> {
  double? _dragFrac; // active drag position (0..1)
  double? _hoverFrac; // trickplay hover position (0..1)
  double? _hoverX;

  Player get _p => widget.player;

  void _seekToFrac(double frac, Duration dur) {
    if (dur <= Duration.zero) return;
    final f = frac.clamp(0.0, 1.0);
    _p.seek(dur * f);
    widget.onInteract();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _p.stream.position,
      initialData: _p.state.position,
      builder: (_, snap) {
        final dur = _p.state.duration;
        final durMs = dur.inMilliseconds;
        final pos = snap.data ?? Duration.zero;
        final playedFrac = _dragFrac ??
            (durMs > 0 ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0);
        final bufFrac = durMs > 0
            ? (_p.state.buffer.inMilliseconds / durMs).clamp(0.0, 1.0)
            : 0.0;
        final info = widget.trickplay;
        final tWidth = widget.trickplayWidth;
        final base = widget.baseUrl;
        const double thumbH = 96;
        final double thumbW = (info != null && info.height > 0)
            ? thumbH * info.width / info.height
            : 160;

        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return MouseRegion(
              opaque: false,
              onHover: (e) {
                if (info == null) return;
                setState(() {
                  _hoverX = e.localPosition.dx.clamp(0.0, w);
                  _hoverFrac = (e.localPosition.dx / w).clamp(0.0, 1.0);
                });
              },
              onExit: (_) {
                if (_hoverFrac != null) {
                  setState(() {
                    _hoverFrac = null;
                    _hoverX = null;
                  });
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekToFrac(d.localPosition.dx / w, dur),
                onHorizontalDragStart: (d) {
                  setState(
                      () => _dragFrac = (d.localPosition.dx / w).clamp(0.0, 1.0));
                  widget.onInteract();
                },
                onHorizontalDragUpdate: (d) {
                  setState(
                      () => _dragFrac = (d.localPosition.dx / w).clamp(0.0, 1.0));
                  widget.onInteract();
                },
                onHorizontalDragEnd: (_) {
                  final f = _dragFrac;
                  if (f != null) _seekToFrac(f, dur);
                  setState(() => _dragFrac = null);
                },
                child: SizedBox(
                  height: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Base track.
                      Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      // Buffered. Anchored left with an explicit width: a
                      // FractionallySizedBox sizes to its fraction and the
                      // center-aligned Stack then centred it, so the fill grew
                      // out from the middle instead of from the start.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: w * bufFrac,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // Played.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: w * playedFrac,
                          height: 5,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // Chapter / segment ticks. Above the played bar so they
                      // stay legible once passed, below the thumb so they never
                      // cover the handle you're dragging.
                      if (dur.inMilliseconds > 0)
                        for (final m in widget.markers)
                          if (m.position > Duration.zero &&
                              m.position < dur)
                            Positioned(
                              left: ((m.position.inMilliseconds /
                                              dur.inMilliseconds) *
                                          w -
                                      1)
                                  .clamp(0.0, w - 2),
                              child: Tooltip(
                                message: m.label,
                                child: Container(
                                  width: 2,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                      // Thumb.
                      Positioned(
                        left: (playedFrac * w - 7).clamp(0.0, w - 14),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                      // Trickplay preview bubble.
                      if (widget.showThumbnailPreview &&
                          info != null &&
                          tWidth != null &&
                          base != null &&
                          widget.client != null &&
                          widget.headers != null &&
                          _hoverFrac != null &&
                          _hoverX != null &&
                          durMs > 0)
                        Positioned(
                          bottom: 26,
                          left: (_hoverX! - thumbW / 2)
                              .clamp(-8.0, (w - thumbW + 8.0).clamp(-8.0, w)),
                          child: _TrickplayThumb(
                            client: widget.client!,
                            baseUrl: base,
                            itemId: widget.itemId,
                            info: info,
                            resolutionWidth: tWidth,
                            headers: widget.headers!,
                            positionMs: (dur * _hoverFrac!).inMilliseconds,
                            thumbWidth: thumbW,
                            thumbHeight: thumbH,
                            label: _fmtTime(dur * _hoverFrac!),
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
    );
  }
}


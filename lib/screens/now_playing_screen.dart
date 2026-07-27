import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../models/radio_station.dart';
import '../state/audio_player.dart';
import '../state/cast.dart';
import '../state/lyrics_provider.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/cast_button.dart';
import '../widgets/control_button.dart';
import '../widgets/glass.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/media_image.dart';
import '../widgets/motion.dart';
import '../widgets/reorder.dart';
import '../widgets/volume_control.dart';

/// Full-screen now-playing: large art, draggable seek bar, transport controls,
/// shuffle and repeat.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    if (audio.isRadio) return const _RadioNowPlaying();
    final track = audio.current;

    // A manual artwork/lyrics flip belongs to the song it was made on. When the
    // track changes, drop back to the preference default rather than carrying a
    // "show lyrics" choice onto a song that may have none.
    ref.listen(
      audioControllerProvider.select((a) => a.current?.id),
      (prev, next) {
        if (prev != next) ref.read(showingLyricsProvider.notifier).reset();
      },
    );
    final controller = ref.read(audioControllerProvider.notifier);
    final player = ref.watch(audioPlayerProvider);
    final theme = Theme.of(context);
    final cast = ref.watch(castControllerProvider);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.playerNothingPlaying)),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(l.playerNowPlaying),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Music can cast to any device, including audio-only speakers. The
          // whole queue is handed to the receiver so Skip advances on-device.
          CastButton(
            videoOnly: false,
            title: track.name,
            queueResolve: () async {
              final session =
                  ref.read(sessionControllerProvider).asData?.value;
              if (session == null) return null;
              final client = ref.read(jellyfinClientProvider);
              final q = ref.read(audioControllerProvider).queue;
              if (q.isEmpty) return null;
              String? img(BaseItemDto t) {
                if (t.primaryImageTag != null) {
                  return client.imageUrl(
                      baseUrl: session.baseUrl,
                      itemId: t.id,
                      type: 'Primary',
                      tag: t.primaryImageTag);
                }
                if (t.albumId != null && t.albumPrimaryImageTag != null) {
                  return client.imageUrl(
                      baseUrl: session.baseUrl,
                      itemId: t.albumId!,
                      type: 'Primary',
                      tag: t.albumPrimaryImageTag);
                }
                return null;
              }

              final items = [
                for (final t in q)
                  {
                    'url': client.castAudioUrl(
                        baseUrl: session.baseUrl,
                        userId: session.userId,
                        itemId: t.id,
                        token: session.accessToken),
                    'contentType': 'audio/mpeg',
                    'title': t.name,
                    'subtitle': t.artists.isNotEmpty
                        ? t.artists.join(', ')
                        : (t.albumArtist ?? ''),
                    if (img(t) != null) 'image': img(t)!,
                  },
              ];
              final start = q.indexWhere((t) => t.id == track.id);
              return (
                items: items,
                startIndex: start < 0 ? 0 : start,
              );
            },
          ),
          _LyricsToggle(track: track),
          _FavoriteButton(track: track),
          IconButton(
            tooltip: l.playerQueue,
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: theme.colorScheme.surface,
              showDragHandle: true,
              builder: (_) => const _QueueSheet(),
            ),
          ),
        ],
      ),
      body: BackdropBackground(
        item: track,
        child: SafeArea(
          child: LayoutBuilder(
          builder: (context, constraints) {
            final cover = math
                .min(constraints.maxWidth - 56, constraints.maxHeight * 0.46)
                .clamp(120.0, 420.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Artwork, or the lyrics in its place. Same footprint, so
                      // the transport below doesn't jump when you flip.
                      _CoverOrLyrics(track: track, player: player, size: cover),
                      const SizedBox(height: 28),
                      Text(track.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (track.artistLine != null)
                        _LinkText(
                          text: track.artistLine!,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          onTap: track.artistItems.isNotEmpty
                              ? () {
                                  final a = track.artistItems.first;
                                  context.push('/artist',
                                      extra: BaseItemDto(id: a.id, name: a.name));
                                }
                              : null,
                        ),
                      if (track.album != null && track.album!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _LinkText(
                            text: track.album!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7)),
                            onTap: track.albumId != null
                                ? () => context.push('/item',
                                    extra: BaseItemDto(
                                        id: track.albumId!,
                                        name: track.album!,
                                        type: 'MusicAlbum'))
                                : null,
                          ),
                        ),
                      const SizedBox(height: 20),
                      _SeekBar(
                        player: player,
                        onSeek: controller.seek,
                        positionOverride: cast.casting
                            ? Duration(milliseconds: cast.positionMs)
                            : null,
                        durationOverride: cast.casting
                            ? Duration(
                                milliseconds: cast.durationMs > 0
                                    ? cast.durationMs
                                    : ((track.runTimeTicks ?? 0) ~/ 10000))
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.shuffle_rounded),
                            isSelected: audio.shuffle,
                            color: audio.shuffle
                                ? theme.colorScheme.primary
                                : null,
                            onPressed: controller.toggleShuffle,
                          ),
                          IconButton(
                            iconSize: 38,
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: controller.previous,
                          ),
                          if (cast.casting)
                            ControlButton(
                              size: 64,
                              icon: cast.playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              tooltip: cast.playing ? l.commonPause : l.commonPlay,
                              onTap: controller.togglePlay,
                            )
                          else
                            StreamBuilder<bool>(
                              stream: player.stream.playing,
                              initialData: player.state.playing,
                              builder: (context, snap) {
                                final playing = snap.data ?? false;
                                return ControlButton(
                                  size: 64,
                                  icon: playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  tooltip: playing ? l.commonPause : l.commonPlay,
                                  onTap: controller.togglePlay,
                                );
                              },
                            ),
                          IconButton(
                            iconSize: 38,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: controller.next,
                          ),
                          IconButton(
                            icon: Icon(audio.repeat == PlaylistMode.single
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded),
                            isSelected: audio.repeat != PlaylistMode.none,
                            color: audio.repeat != PlaylistMode.none
                                ? theme.colorScheme.primary
                                : null,
                            onPressed: controller.cycleRepeat,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      VolumeSlider(player: player),
                      const SizedBox(height: 12),
                      _UpNextPeek(
                        audio: audio,
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: theme.colorScheme.surface,
                          showDragHandle: true,
                          builder: (_) => const _QueueSheet(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

/// Position slider that follows playback but holds still while dragging.
/// Now Playing for internet radio: station logo, name, live ICY title, and
/// play/stop + volume + cast. No scrubber or skip (it's a live stream).
class _RadioNowPlaying extends ConsumerWidget {
  const _RadioNowPlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    final player = ref.watch(audioPlayerProvider);
    final s = audio.radioStation;
    if (s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(l.radioNowPlaying),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          CastButton(
            videoOnly: false,
            title: s.name,
            resolve: () async => (
              url: s.url,
              contentType: s.url.toLowerCase().contains('.m3u8')
                  ? 'application/x-mpegurl'
                  : 'audio/mpeg',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // A soft accent-tinted backdrop (a nod to the art without sampling it).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.10), scheme.surface),
                    scheme.surface,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 840;
              final info = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _info(context, ref, l, audio, player, s, theme),
              );
              // Wide: art on the LEFT, info on the RIGHT, the whole pair centered
              // both ways on screen. Narrow: the same, stacked in a column.
              final content = wide
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _hero(context, ref, player, audio, s, theme, 280),
                        const SizedBox(width: 48),
                        info,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _hero(context, ref, player, audio, s, theme, 250),
                        const SizedBox(height: 28),
                        info,
                      ],
                    );
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
                child: ConstrainedBox(
                  // Fill the viewport so Center puts the block in the true middle
                  // of the screen; scrolls only if it's ever too tall.
                  constraints: BoxConstraints(minHeight: c.maxHeight - 44),
                  child: Center(child: content),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, WidgetRef ref, Player player,
      AudioState audio, RadioStation s, ThemeData theme, double size) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snap) {
        final art = audio.radioArtwork;
        final hasArt = art != null && art.isNotEmpty;
        return _AuraGlow(
          playing: snap.data ?? false,
          borderRadius: 18,
          color: theme.colorScheme.primary,
          child: Container(
            width: size,
            height: size,
            // Album art fills the card; a logo-only station has its logo
            // contained (padded) as the hero itself.
            padding: hasArt ? EdgeInsets.zero : EdgeInsets.all(size * 0.16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: hasArt
                ? Image.network(art,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    // If the resolved art URL fails, drop it so we fall back to
                    // the station logo AND the redundant logo chip disappears.
                    errorBuilder: (context, _, _) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ref
                            .read(audioControllerProvider.notifier)
                            .clearRadioArtwork(art);
                      });
                      return _radioLogo(theme, s);
                    })
                : _radioLogo(theme, s),
          ),
        );
      },
    );
  }

  Widget _info(BuildContext context, WidgetRef ref, AppLocalizations l,
      AudioState audio, Player player, RadioStation s, ThemeData theme) {
    final scheme = theme.colorScheme;
    final controller = ref.read(audioControllerProvider.notifier);
    final hasIcy = audio.radioTitle != null && audio.radioTitle!.isNotEmpty;
    final hasArt = audio.radioArtwork != null && audio.radioArtwork!.isNotEmpty;
    const tAlign = TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // A small station-logo chip when album art is the hero, so you still
        // know which station you're on. Dropped when the logo IS the hero.
        if (hasArt && s.favicon != null && s.favicon!.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(s.favicon!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 12),
        ],
        Text(s.name,
            textAlign: tAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(hasIcy ? audio.radioTitle! : l.radioLiveStream,
            textAlign: tAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        _liveRow(context, l, audio, controller, theme),
        const SizedBox(height: 14),
        VolumeSlider(player: player),
        const SizedBox(height: 10),
        _controls(context, l, audio, controller, player, theme),
      ],
    );
  }

  /// The live status: a scrub bar on seekable streams, otherwise the LIVE pill
  /// (red at the edge) plus a "-M:SS" catch-up when behind.
  Widget _liveRow(BuildContext context, AppLocalizations l, AudioState audio,
      AudioController controller, ThemeData theme) {
    final scheme = theme.colorScheme;
    if (audio.radioSeekable && audio.radioWindow.inSeconds > 3) {
      return _RadioScrubBar(
        window: audio.radioWindow,
        behind: audio.radioBehindLive,
        onSeekBehind: controller.radioSeekBehind,
        onGoLive: controller.radioGoLive,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!audio.radioAtLive) ...[
          Text('-${_fmtDur(audio.radioBehindLive)}',
              style: TextStyle(
                  color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
        ],
        radioLiveBadge(context,
            atLive: audio.radioAtLive, onTap: controller.radioGoLive),
      ],
    );
  }

  Widget _controls(BuildContext context, AppLocalizations l, AudioState audio,
      AudioController controller, Player player, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (audio.radioSeekable) ...[
          ControlButton(
            icon: Icons.fast_rewind_rounded,
            tooltip: l.radioRewind,
            size: 32,
            grow: false,
            color: scheme.onSurfaceVariant,
            onTap: () => controller.radioSeekBy(const Duration(seconds: -15)),
          ),
          const SizedBox(width: 10),
        ],
        StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            return ControlButton(
              icon: playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              tooltip: playing ? l.commonPause : l.commonPlay,
              size: 72,
              onTap: controller.togglePlay,
            );
          },
        ),
        if (audio.radioSeekable) ...[
          const SizedBox(width: 10),
          ControlButton(
            icon: Icons.fast_forward_rounded,
            tooltip: l.radioSkip,
            size: 32,
            grow: false,
            color: scheme.onSurfaceVariant,
            onTap: () => controller.radioSeekBy(const Duration(seconds: 15)),
          ),
        ],
      ],
    );
  }

  /// Station logo (contained) with a radio-icon fallback, used when there's no
  /// per-song album art to show.
  Widget _radioLogo(ThemeData theme, RadioStation s) =>
      s.favicon != null && s.favicon!.isNotEmpty
          ? Image.network(s.favicon!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => Icon(Icons.radio_rounded,
                  size: 80, color: theme.colorScheme.onSurfaceVariant))
          : Icon(Icons.radio_rounded,
              size: 80, color: theme.colorScheme.onSurfaceVariant);
}

String _fmtDur(Duration d) {
  final s = d.inSeconds.abs();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The LIVE pill, matching the video player's live badge: solid red at the edge
/// (not tappable), outlined when behind (tap to catch up).
Widget radioLiveBadge(BuildContext context,
    {required bool atLive, VoidCallback? onTap}) {
  final scheme = Theme.of(context).colorScheme;
  final l = AppLocalizations.of(context);
  const red = Color(0xFFE53935);
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: atLive ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: atLive ? red : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: atLive ? red : scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle,
              size: 7,
              color: atLive
                  ? Colors.white
                  : scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 5),
          Text(l.playerBadgeLive,
              style: TextStyle(
                  color: atLive ? Colors.white : scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ],
      ),
    ),
  );
}

/// A live time-shift scrub bar: drag to rewind within the buffered window, with
/// the current offset on the left and the LIVE badge (tap to catch up) at right.
class _RadioScrubBar extends StatefulWidget {
  final Duration window;
  final Duration behind;
  final Future<void> Function(Duration behind) onSeekBehind;
  final Future<void> Function() onGoLive;
  const _RadioScrubBar({
    required this.window,
    required this.behind,
    required this.onSeekBehind,
    required this.onGoLive,
  });

  @override
  State<_RadioScrubBar> createState() => _RadioScrubBarState();
}

class _RadioScrubBarState extends State<_RadioScrubBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final w = widget.window.inSeconds.clamp(1, 1 << 30).toDouble();
    // 0 = oldest buffered, 1 = live edge.
    final value =
        _drag ?? (1 - (widget.behind.inSeconds / w)).clamp(0.0, 1.0);
    final atLive = _drag == null && widget.behind.inMilliseconds < 2500;
    // Seek bar and the LIVE badge on one row, to its RIGHT — like the video
    // player's transport bar.
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                setState(() => _drag = null);
                widget.onSeekBehind(Duration(seconds: ((1 - v) * w).round()));
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        radioLiveBadge(context, atLive: atLive, onTap: widget.onGoLive),
      ],
    );
  }
}

/// Wraps the radio logo/art in a soft accent glow that gently pulses while the
/// station is playing (a sound "aura"), still when paused. Honours reduced
/// motion. Mirrors LiftTrace's playing-state art pulse.
class _AuraGlow extends StatefulWidget {
  final bool playing;
  final double borderRadius;
  final Color color;
  final Widget child;
  const _AuraGlow({
    required this.playing,
    required this.borderRadius,
    required this.color,
    required this.child,
  });

  @override
  State<_AuraGlow> createState() => _AuraGlowState();
}

class _AuraGlowState extends State<_AuraGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AuraGlow old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Paused (or reduced motion) shows the art with no glow.
    if (!widget.playing || reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.32 * t),
                blurRadius: 34 * t,
                spreadRadius: 7 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SeekBar extends StatefulWidget {
  final Player player;
  final void Function(Duration) onSeek;
  // When set (casting), the bar shows the cast device's position/duration
  // instead of the local player's.
  final Duration? positionOverride;
  final Duration? durationOverride;
  const _SeekBar({
    required this.player,
    required this.onSeek,
    this.positionOverride,
    this.durationOverride,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: widget.player.state.position,
      builder: (context, snap) {
        final position =
            widget.positionOverride ?? snap.data ?? Duration.zero;
        final duration =
            widget.durationOverride ?? widget.player.state.duration;
        final maxMs = duration.inMilliseconds.toDouble();
        // Guard: a cast device can report an unknown/zero duration (maxMs <= 0),
        // and clamp(0.0, maxMs) throws when the upper bound is below the lower.
        final posMs = maxMs <= 0
            ? 0.0
            : position.inMilliseconds.toDouble().clamp(0.0, maxMs);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                min: 0,
                max: maxMs <= 0 ? 1 : maxMs,
                value: _dragValue ?? (maxMs <= 0 ? 0 : posMs),
                onChanged: maxMs <= 0
                    ? null
                    : (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.onSeek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(position),
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(_fmt(duration),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// The up-next queue: reorder, tap to jump, or remove tracks. Reflects the
/// player's real order (so it stays correct after shuffle).
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final theme = Theme.of(context);
    final currentId = audio.current?.id;

    // A fixed-height sheet (not DraggableScrollableSheet): its internal
    // LayoutBuilder conflicts with ReorderableListView and throws
    // "_RenderLayoutBuilder was mutated" mid-reorder.
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(l.playerUpNext,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: audio.queue.length,
                // ignore: deprecated_member_use
                onReorder: controller.moveQueue,
                itemBuilder: (context, i) {
                  final t = audio.queue[i];
                  final isCurrent = t.id == currentId;
                  return dragAnywhere(
                    key: ValueKey('${t.id}_$i'),
                    index: i,
                    child: ListTile(
                    onTap: () {
                      controller.jumpTo(i);
                      Navigator.of(context).pop();
                    },
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drag_indicator, color: dragGripColor(context)),
                        const SizedBox(width: 6),
                        isCurrent
                            ? Icon(Icons.equalizer_rounded,
                                color: theme.colorScheme.primary)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: MediaImage(
                                      item: t,
                                      placeholderIcon:
                                          Icons.music_note_rounded),
                                ),
                              ),
                      ],
                    ),
                    title: Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? theme.colorScheme.primary : null,
                        )),
                    subtitle: t.artistLine != null
                        ? Text(t.artistLine!,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    // The whole row is draggable (long-press / press-drag), so a
                    // single Remove action is all that's needed here.
                    trailing: IconButton(
                      tooltip: l.commonRemove,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => controller.removeAt(i),
                    ),
                  ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heart toggle for the current track. Optimistic + resets when the track
/// changes, since the audio queue items aren't backed by a refreshable provider.
class _FavoriteButton extends ConsumerStatefulWidget {
  final BaseItemDto track;
  const _FavoriteButton({required this.track});

  @override
  ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton> {
  late bool _fav = widget.track.userData.isFavorite;
  late String _forId = widget.track.id;

  @override
  Widget build(BuildContext context) {
    // Follow track changes without losing an in-flight optimistic toggle.
    if (widget.track.id != _forId) {
      _forId = widget.track.id;
      _fav = widget.track.userData.isFavorite;
    }
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: _fav ? l.playerRemoveFavorite : l.playerAddFavorite,
      isSelected: _fav,
      color: _fav ? scheme.primary : null,
      icon: Icon(_fav ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      onPressed: () async {
        final session = ref.read(sessionControllerProvider).asData?.value;
        if (session == null) return;
        final next = !_fav;
        setState(() => _fav = next);
        try {
          await ref.read(jellyfinClientProvider).setFavorite(
                baseUrl: session.baseUrl,
                userId: session.userId,
                token: session.accessToken,
                itemId: widget.track.id,
                favorite: next,
              );
        } catch (_) {
          if (mounted) setState(() => _fav = !next);
        }
      },
    );
  }
}

/// A compact "Up Next" pill showing the following track; opens the full queue.
class _UpNextPeek extends StatelessWidget {
  final AudioState audio;
  final VoidCallback onTap;
  const _UpNextPeek({required this.audio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final currentId = audio.current?.id;
    final idx = currentId == null
        ? -1
        : audio.queue.indexWhere((t) => t.id == currentId);
    if (idx < 0 || idx + 1 >= audio.queue.length) {
      return const SizedBox.shrink();
    }
    final nextTrack = audio.queue[idx + 1];
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: MediaImage(
                        item: nextTrack,
                        placeholderIcon: Icons.music_note_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.playerUpNext,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          )),
                      const SizedBox(height: 2),
                      Text(nextTrack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Icon(Icons.queue_music_rounded, size: 20),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered text that reads as a link and becomes tappable when [onTap] is set,
/// otherwise renders as plain text (e.g. an artist with no navigable id).
class _LinkText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;
  const _LinkText({required this.text, this.style, this.onTap});

  @override
  Widget build(BuildContext context) {
    final child = Text(text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style);
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}

/// The app-bar button that flips between artwork and lyrics.
///
/// Only present when the track actually has lyrics, so it never offers a view
/// that would just say "no lyrics".
class _LyricsToggle extends ConsumerWidget {
  final BaseItemDto track;
  const _LyricsToggle({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(lyricsKeyFor(track))).asData?.value;
    if (lyrics == null || lyrics.isEmpty) return const SizedBox.shrink();

    final auto = ref.watch(preferencesProvider).asData?.value
            .showLyricsAutomatically ??
        true;
    final showing = ref.watch(showingLyricsProvider) ?? auto;

    return IconButton(
      tooltip: showing
          ? AppLocalizations.of(context).playerShowArtwork
          : AppLocalizations.of(context).playerShowLyrics,
      isSelected: showing,
      icon: Icon(showing ? Icons.image_rounded : Icons.lyrics_rounded),
      onPressed: () => ref.read(showingLyricsProvider.notifier).set(!showing),
    );
  }
}

/// The cover, or the lyrics occupying the same square.
class _CoverOrLyrics extends ConsumerWidget {
  final BaseItemDto track;
  final Player player;
  final double size;

  const _CoverOrLyrics({
    required this.track,
    required this.player,
    required this.size,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(lyricsKeyFor(track))).asData?.value;
    final hasLyrics = lyrics != null && !lyrics.isEmpty;

    final auto = ref.watch(preferencesProvider).asData?.value
            .showLyricsAutomatically ??
        true;
    final showing = hasLyrics && (ref.watch(showingLyricsProvider) ?? auto);

    if (showing) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: LyricsView(lyrics: lyrics, player: player),
      );
    }

    return Hero(
      tag: 'nowPlayingArt',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: size,
            height: size,
            child: MediaImage(
                item: track, placeholderIcon: Icons.music_note_rounded),
          ),
        ),
      ),
    );
  }
}

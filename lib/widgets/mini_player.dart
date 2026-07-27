import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/radio_station.dart';
import '../state/audio_player.dart';
import 'control_button.dart';
import 'glass.dart';
import 'media_image.dart';
import 'volume_control.dart';

/// Compact now-playing bar shown app-wide while audio is loaded.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final player = ref.watch(audioPlayerProvider);
    final scheme = Theme.of(context).colorScheme;

    // Radio uses a distinct bar: no progress/seek/skip (it's a live stream), a
    // Stop instead, and the station logo + live ICY title.
    if (audio.isRadio) {
      return _RadioMiniBar(
          station: audio.radioStation!,
          title: audio.radioTitle,
          artwork: audio.radioArtwork,
          player: player,
          controller: controller);
    }

    final track = audio.current;
    if (track == null) return const SizedBox.shrink();

    return GlassSurface(
      blur: 26,
      opacity: 0.6,
      border: Border(
        top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniProgress(player: player),
            SizedBox(
          height: 63,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/nowplaying'),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Hero(
                        tag: 'nowPlayingArt',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: MediaImage(
                                item: track,
                                placeholderIcon: Icons.music_note_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (track.artistLine != null)
                              Text(track.artistLine!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              VolumeMenuButton(player: player),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: controller.previous,
              ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return ControlButton(
                    size: 34,
                    icon: playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    tooltip: playing
                        ? AppLocalizations.of(context).commonPause
                        : AppLocalizations.of(context).commonPlay,
                    onTap: controller.togglePlay,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: controller.next,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The mini bar while an internet-radio station is playing: logo, station name
/// + live ICY title, play/pause and Stop. No progress bar or skip (it's live).
class _RadioMiniBar extends StatelessWidget {
  final RadioStation station;
  final String? title;
  final String? artwork;
  final Player player;
  final AudioController controller;
  const _RadioMiniBar({
    required this.station,
    required this.title,
    required this.artwork,
    required this.player,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasIcy = title != null && title!.isNotEmpty;
    // Prefer per-song album art (when the stream provides it) over the logo.
    final img = (artwork != null && artwork!.isNotEmpty)
        ? artwork!
        : (station.favicon ?? '');
    return GlassSurface(
      blur: 26,
      opacity: 0.6,
      border: Border(
        top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 65,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => context.push('/nowplaying'),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: img.isNotEmpty
                                ? Image.network(img,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _logo(scheme))
                                : _logo(scheme),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(hasIcy ? title! : station.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(hasIcy ? station.name : 'Radio',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VolumeMenuButton(player: player),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: player.state.playing,
                  builder: (context, snap) {
                    final playing = snap.data ?? false;
                    return ControlButton(
                      size: 34,
                      icon: playing
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      tooltip: playing
                          ? AppLocalizations.of(context).commonPause
                          : AppLocalizations.of(context).commonPlay,
                      onTap: controller.togglePlay,
                    );
                  },
                ),
                ControlButton(
                  size: 26,
                  grow: false,
                  icon: Icons.stop_rounded,
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  color: scheme.onSurfaceVariant,
                  onTap: controller.stopRadio,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.radio_rounded, color: scheme.onSurfaceVariant),
      );
}

/// A hairline progress bar across the top of the mini player.
class _MiniProgress extends StatelessWidget {
  final Player player;
  const _MiniProgress({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = player.state.duration;
        final value = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        return LinearProgressIndicator(
          value: value,
          minHeight: 2,
          backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
          valueColor: AlwaysStoppedAnimation(scheme.primary),
        );
      },
    );
  }
}

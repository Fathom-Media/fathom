import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:media_kit/media_kit.dart';

import '../state/audio_player.dart';
import 'glass.dart';
import 'media_image.dart';
import 'volume_control.dart';

/// Compact now-playing bar shown app-wide while audio is loaded.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioControllerProvider);
    final track = audio.current;
    if (track == null) return const SizedBox.shrink();

    final controller = ref.read(audioControllerProvider.notifier);
    final player = ref.watch(audioPlayerProvider);
    final scheme = Theme.of(context).colorScheme;

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
                  return IconButton(
                    iconSize: 34,
                    icon: Icon(playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded),
                    onPressed: controller.togglePlay,
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

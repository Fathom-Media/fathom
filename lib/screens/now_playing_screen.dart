import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/audio_player.dart';
import '../state/lyrics_provider.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/glass.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/media_image.dart';
import '../widgets/volume_control.dart';

/// Full-screen now-playing: large art, draggable seek bar, transport controls,
/// shuffle and repeat.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
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
                      _SeekBar(player: player, onSeek: controller.seek),
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
                          StreamBuilder<bool>(
                            stream: player.stream.playing,
                            initialData: player.state.playing,
                            builder: (context, snap) {
                              final playing = snap.data ?? false;
                              return IconButton(
                                iconSize: 64,
                                icon: Icon(playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded),
                                onPressed: controller.togglePlay,
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
class _SeekBar extends StatefulWidget {
  final Player player;
  final void Function(Duration) onSeek;
  const _SeekBar({required this.player, required this.onSeek});

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
        final position = snap.data ?? Duration.zero;
        final duration = widget.player.state.duration;
        final maxMs = duration.inMilliseconds.toDouble();
        final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
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
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: audio.queue.length,
                // ignore: deprecated_member_use
                onReorder: controller.moveQueue,
                itemBuilder: (context, i) {
                  final t = audio.queue[i];
                  final isCurrent = t.id == currentId;
                  return ListTile(
                    key: ValueKey('${t.id}_$i'),
                    onTap: () {
                      controller.jumpTo(i);
                      Navigator.of(context).pop();
                    },
                    leading: isCurrent
                        ? Icon(Icons.equalizer_rounded,
                            color: theme.colorScheme.primary)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: MediaImage(
                                  item: t,
                                  placeholderIcon: Icons.music_note_rounded),
                            ),
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
                    // The whole row is draggable (default handles), so a single
                    // Remove action is all that's needed here.
                    trailing: IconButton(
                      tooltip: l.commonRemove,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => controller.removeAt(i),
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

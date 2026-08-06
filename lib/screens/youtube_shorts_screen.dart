import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/youtube_video.dart';
import '../services/tv_mode.dart';
import '../services/youtube_streams.dart';
import '../state/audio_player.dart';
import '../state/youtube_providers.dart';
import '../widgets/add_to_youtube_playlist.dart';
import '../widgets/youtube_actions.dart';

/// A vertical, swipeable Shorts viewer — one Short per full-screen page, swipe
/// up/down to move. Scoped to the list it was opened from (e.g. a channel's
/// Shorts tab), paging in more of that list on demand. Endless cross-channel
/// discovery (YouTube's reel sequence) is a planned follow-up; this stays within
/// the source list.
///
/// Only current ± 1 pages hold a live player (a small pool that recycles as you
/// swipe); everything else is just its thumbnail, so memory stays flat.
class YoutubeShortsScreen extends ConsumerStatefulWidget {
  final List<YoutubeVideo> shorts;
  final int startIndex;

  /// Continuation token for the source list, to page in more Shorts.
  final String? continuation;

  const YoutubeShortsScreen({
    super.key,
    required this.shorts,
    this.startIndex = 0,
    this.continuation,
  });

  @override
  ConsumerState<YoutubeShortsScreen> createState() =>
      _YoutubeShortsScreenState();
}

class _YoutubeShortsScreenState extends ConsumerState<YoutubeShortsScreen> {
  late final PageController _pageController;
  late List<YoutubeVideo> _shorts;
  late int _index;
  String? _continuation;
  bool _loadingMore = false;
  bool _muted = false;

  // Windowed player pool: index -> player. Only current ± 1 are kept alive.
  final Map<int, Player> _players = {};
  final Map<int, VideoController> _controllers = {};
  // Resolved muxed URL per video id (null = resolve failed), so re-entering a
  // page never re-hits the network.
  final Map<String, String?> _urlCache = {};

  bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _shorts = List.of(widget.shorts);
    _index = widget.startIndex.clamp(0, _shorts.isEmpty ? 0 : _shorts.length - 1);
    _continuation = widget.continuation;
    _pageController = PageController(initialPage: _index);
    // Shorts are vertical: hold portrait and go immersive on a phone while the
    // viewer is up. No-op on desktop/TV.
    if (_mobile && !isTvDevice) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
          overlays: const []);
      SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateWindow());
  }

  @override
  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    _controllers.clear();
    _pageController.dispose();
    if (_mobile && !isTvDevice) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  /// Bring the pool in line with the current index: create players for the
  /// current ± 1 window, dispose any outside it, and play the current one while
  /// the neighbours sit preloaded and paused.
  void _updateWindow() {
    final keep = <int>{
      for (var d = -1; d <= 1; d++) _index + d,
    }.where((i) => i >= 0 && i < _shorts.length).toSet();

    for (final i in _players.keys.toList()) {
      if (!keep.contains(i)) {
        _controllers.remove(i);
        _players.remove(i)?.dispose();
      }
    }
    for (final i in keep) {
      if (!_players.containsKey(i)) {
        final player = Player();
        _players[i] = player;
        _controllers[i] = VideoController(player);
        unawaited(_open(player, i));
      }
    }
    for (final entry in _players.entries) {
      if (entry.key == _index) {
        unawaited(entry.value.play());
        unawaited(entry.value.setVolume(_muted ? 0 : 100));
      } else {
        unawaited(entry.value.pause());
      }
    }
    if (mounted) setState(() {});
    unawaited(_maybeLoadMore());
  }

  Future<void> _open(Player player, int index) async {
    try {
      await player.setPlaylistMode(PlaylistMode.single); // loop the Short
      final url = await _resolveUrl(_shorts[index].id);
      // Bail if this player was recycled out of the window while resolving.
      if (url == null || !_players.containsValue(player)) return;
      await player.open(Media(url), play: index == _index);
      await player.setVolume(_muted ? 0 : 100);
    } catch (_) {}
  }

  Future<String?> _resolveUrl(String videoId) async {
    if (_urlCache.containsKey(videoId)) return _urlCache[videoId];
    try {
      final s = await resolveYoutubeStreams(
          'https://www.youtube.com/watch?v=$videoId');
      // Prefer the self-contained muxed stream (has audio); Shorts are low-res
      // so it almost always exists. Fall back to the best video-only rendition.
      final url =
          s.muxedUrl ?? (s.qualities.isNotEmpty ? s.qualities.first.url : null);
      _urlCache[videoId] = url;
      return url;
    } catch (_) {
      _urlCache[videoId] = null;
      return null;
    }
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore ||
        _continuation == null ||
        _index < _shorts.length - 2) {
      return;
    }
    _loadingMore = true;
    try {
      final more =
          await ref.read(youtubeInnerTubeProvider).channelTabMore(_continuation!);
      final seen = {for (final v in _shorts) v.id};
      final fresh = more.videos.where((v) => !seen.contains(v.id)).toList();
      if (!mounted) return;
      setState(() {
        _shorts = [..._shorts, ...fresh];
        _continuation = more.videos.isEmpty ? null : more.continuation;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  void _onPageChanged(int i) {
    _index = i;
    _updateWindow();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _players[_index]?.setVolume(_muted ? 0 : 100);
  }

  @override
  Widget build(BuildContext context) {
    if (_shorts.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _shorts.length,
            itemBuilder: (context, i) => _ShortPage(
              short: _shorts[i],
              player: i == _index ? _players[i] : null,
              controller: _controllers[i],
              muted: _muted,
            ),
          ),
          // Top overlay: back + mute, clear of the status bar.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white),
                    onPressed: _toggleMute,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One full-screen Short: the video (or its thumbnail until a player is bound),
/// tap-to-pause, a bottom metadata scrim, a right-side action rail, and a slim
/// progress bar.
class _ShortPage extends ConsumerStatefulWidget {
  final YoutubeVideo short;
  final Player? player;
  final VideoController? controller;
  final bool muted;

  const _ShortPage({
    required this.short,
    required this.player,
    required this.controller,
    required this.muted,
  });

  @override
  ConsumerState<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends ConsumerState<_ShortPage> {
  bool _flashPlay = false;

  void _tap() {
    final p = widget.player;
    if (p == null) return;
    p.playOrPause();
    setState(() => _flashPlay = true);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _flashPlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final short = widget.short;
    final controller = widget.controller;
    return GestureDetector(
      onTap: _tap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video, or the thumbnail while it's off-window / still opening.
          if (controller != null)
            Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            )
          else
            Image.network(
              short.thumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),

          // Center play/pause flash on tap.
          if (_flashPlay && widget.player != null)
            Center(
              child: StreamBuilder<bool>(
                stream: widget.player!.stream.playing,
                initialData: widget.player!.state.playing,
                builder: (context, snap) => Icon(
                  (snap.data ?? true)
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 76,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),

          // Bottom + right controls.
          _Overlay(short: short),

          // Slim progress bar pinned to the very bottom.
          if (widget.player != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Progress(player: widget.player!),
            ),
        ],
      ),
    );
  }
}

/// Bottom-left metadata + right-side Fathom action rail. The rail is the video
/// action set (add to playlist, listen, copy link) laid out vertically — the
/// same actions the watch page offers, since Fathom has no account to like with.
class _Overlay extends ConsumerWidget {
  final YoutubeVideo short;
  const _Overlay({required this.short});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        // Right rail.
        Positioned(
          right: 6,
          bottom: 96,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: Icons.playlist_add_rounded,
                  label: l.ytAddToPlaylist,
                  onTap: () => showAddToYoutubePlaylist(context, short),
                ),
                const SizedBox(height: 18),
                if (!isTvDevice)
                  _RailButton(
                    icon: Icons.headset_rounded,
                    label: l.ytListen,
                    onTap: () => ref
                        .read(audioControllerProvider.notifier)
                        .playYoutubeAudio(youtubeAudioItemOf(short)),
                  ),
                if (!isTvDevice) const SizedBox(height: 18),
                _RailButton(
                  icon: Icons.link_rounded,
                  label: l.ytCopyLink,
                  onTap: () {
                    Clipboard.setData(ClipboardData(
                        text: 'https://www.youtube.com/watch?v=${short.id}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.ytLinkCopied)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Bottom-left metadata over a scrim.
        Positioned(
          left: 0,
          right: 72,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (short.author.isNotEmpty)
                    GestureDetector(
                      onTap: (short.channelId?.isEmpty ?? true)
                          ? null
                          : () => context.push('/youtube/channel', extra: (
                                channelId: short.channelId!,
                                title: short.author,
                              )),
                      child: Text(
                        short.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    short.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RailButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final Player player;
  const _Progress({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snap) {
        final dur = player.state.duration.inMilliseconds;
        final pos = (snap.data ?? Duration.zero).inMilliseconds;
        final value = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
        return LinearProgressIndicator(
          value: value,
          minHeight: 2.5,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Colors.white),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../api/jellyfin_client.dart';
import '../models/base_item.dart';
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

  const AudioState({
    this.queue = const [],
    this.current,
    this.shuffle = false,
    this.repeat = PlaylistMode.none,
  });

  bool get hasTrack => current != null;

  AudioState copyWith({
    List<BaseItemDto>? queue,
    BaseItemDto? current,
    bool? shuffle,
    PlaylistMode? repeat,
  }) =>
      AudioState(
        queue: queue ?? this.queue,
        current: current ?? this.current,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
      );
}

/// Owns the queue, mirrors the player's track index for the UI, and reports
/// playback to the server (now-playing + play counts, i.e. scrobbling).
class AudioController extends Notifier<AudioState> {
  Player get _player => ref.read(audioPlayerProvider);
  Timer? _progressTimer;
  String? _reportedId;
  int _lastPositionTicks = 0;
  final Map<String, BaseItemDto> _byId = {};

  // The stream URL always contains /Audio/{itemId}/stream — resolve the current
  // track by URL so it stays correct even after shuffling reorders the queue.
  static final _idPattern = RegExp(r'/Audio/([^/]+)/stream');
  String? _itemIdFromUri(String uri) => _idPattern.firstMatch(uri)?.group(1);

  @override
  AudioState build() {
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
      } else if (ordered.isNotEmpty) {
        state = state.copyWith(queue: ordered);
      }
    });
    final subPosition = _player.stream.position.listen((p) {
      _lastPositionTicks = p.inMicroseconds * 10;
    });
    _progressTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _reportProgress());
    ref.onDispose(() {
      subPlaylist.cancel();
      subPosition.cancel();
      _progressTimer?.cancel();
      _reportStopped();
    });
    return const AudioState();
  }

  ({Session session, JellyfinClient client})? _ctx() {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return null;
    return (session: session, client: ref.read(jellyfinClientProvider));
  }

  Future<void> playQueue(List<BaseItemDto> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    final c = _ctx();
    if (c == null) return;
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
    state = state.copyWith(queue: tracks, current: tracks[startIndex]);
    await _player.open(Playlist(medias, index: startIndex));
    _lastPositionTicks = 0;
    _reportStart(tracks[startIndex].id);
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

  Future<void> togglePlay() => _player.playOrPause();
  Future<void> next() => _player.next();
  Future<void> previous() => _player.previous();
  Future<void> seek(Duration position) => _player.seek(position);

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

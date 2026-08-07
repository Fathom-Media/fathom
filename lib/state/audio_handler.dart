import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The initialized OS media session, or null when it isn't available (desktop,
/// or a failed init). Overridden in main() after [AudioService.init].
final audioHandlerProvider = Provider<FathomAudioHandler?>((_) => null);

/// Bridges the app's music playback to the system media session: the
/// notification, lock-screen controls, and headset/Bluetooth transport buttons.
///
/// It owns no player. The control callbacks are wired by [AudioController] once
/// the music player exists, and now-playing/playback state is pushed in from
/// there via [setNowPlaying] and [setPlayback]. Keeping the handler dumb avoids
/// coupling the (pre-runApp) media session to the (post-runApp) Riverpod graph.
class FathomAudioHandler extends BaseAudioHandler with SeekHandler {
  FathomAudioHandler() {
    // Seed an idle state immediately so audio_service always has something to
    // build a notification from. Without an initial state, Android 14+ kills the
    // foreground service for never calling startForeground().
    playbackState.add(PlaybackState(
      controls: const [MediaControl.play],
      // Advertise search + play-from-id even while idle, so the car shows the
      // search button and can start playback from a cold, stopped state.
      systemActions: const {
        MediaAction.playFromSearch,
        MediaAction.playFromMediaId,
      },
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function()? onStop;
  Future<void> Function(Duration)? onSeek;

  // Android Auto (and any MediaBrowser client): the browsable content tree and
  // "play this" routing. Wired by [AudioController] once the app data + player
  // exist; null until then, so a cold browse simply returns an empty tree rather
  // than crashing the car's media picker.
  Future<List<MediaItem>> Function(String parentMediaId)? onGetChildren;
  Future<void> Function(String mediaId)? onPlayFromMediaId;
  Future<List<MediaItem>> Function(String query)? onSearch;
  Future<void> Function(String query)? onPlayFromSearch;

  // Now-playing controls: shuffle / repeat toggles, jump-to-queue-item, and a
  // custom Favorite action. Wired by [AudioController].
  Future<void> Function(bool enabled)? onSetShuffle;
  Future<void> Function(AudioServiceRepeatMode mode)? onSetRepeat;
  Future<void> Function(int index)? onSkipToQueueItem;
  Future<void> Function()? onToggleFavorite;
  // Shuffle/Repeat as custom actions too: some head units (and LIVI) only
  // render custom buttons on the now-playing screen, not the standard toggles.
  Future<void> Function()? onToggleShuffle;
  Future<void> Function()? onCycleRepeat;

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> stop() async => onStop?.call();

  @override
  Future<void> seek(Duration position) async => onSeek?.call(position);

  // ---- Android Auto browsing ------------------------------------------------
  // The car (or any MediaBrowser client) calls these to build its browse UI and
  // to start playback from a tapped item / voice search. All routed to the
  // wired callbacks; an unwired handler yields an empty tree and no-op plays.

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) async =>
      (await onGetChildren?.call(parentMediaId)) ?? const [];

  @override
  Future<void> playFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) async =>
      onPlayFromMediaId?.call(mediaId);

  @override
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) async =>
      (await onSearch?.call(query)) ?? const [];

  @override
  Future<void> playFromSearch(String query,
          [Map<String, dynamic>? extras]) async =>
      onPlayFromSearch?.call(query);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async =>
      onSetShuffle?.call(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async =>
      onSetRepeat?.call(repeatMode);

  @override
  Future<void> skipToQueueItem(int index) async =>
      onSkipToQueueItem?.call(index);

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'favorite':
        await onToggleFavorite?.call();
      case 'shuffle':
        await onToggleShuffle?.call();
      case 'repeat':
        await onCycleRepeat?.call();
    }
    return null;
  }

  /// Publish the current track's metadata for the notification/lock screen.
  void setNowPlaying(MediaItem item) => mediaItem.add(item);

  /// Publish transport state (playing/paused, position, buffered) so the
  /// notification's controls and scrubber reflect the player.
  ///
  /// [radio] switches to the live-stream control set: just play/pause. Radio has
  /// no track queue, so the music skip buttons would be dead no-ops, and a stop
  /// button only renders as a stray square in the media player. One control is
  /// all a live stream needs.
  void setPlayback({
    required bool playing,
    required bool buffering,
    required Duration position,
    required Duration buffered,
    double speed = 1.0,
    bool radio = false,
    bool shuffle = false,
    AudioServiceRepeatMode repeat = AudioServiceRepeatMode.none,
    bool? favorite, // null = no Favorite control (radio / YouTube)
    int? queueIndex, // which queue row the car highlights as "now playing"
    bool musicQueue = false, // show shuffle/repeat (library music only)
  }) {
    final controls = <MediaControl>[];
    if (radio) {
      controls.add(playing ? MediaControl.pause : MediaControl.play);
    } else {
      controls
        ..add(MediaControl.skipToPrevious)
        ..add(playing ? MediaControl.pause : MediaControl.play)
        ..add(MediaControl.skipToNext);
    }
    if (musicQueue) {
      // Shuffle + Repeat as custom buttons. Custom actions have no built-in
      // on/off state, so "active" is shown with a filled-chip icon variant.
      controls.add(MediaControl.custom(
        androidIcon:
            shuffle ? 'drawable/ic_auto_shuffle_on' : 'drawable/ic_auto_shuffle',
        label: shuffle ? 'Shuffle on' : 'Shuffle off',
        name: 'shuffle',
      ));
      controls.add(MediaControl.custom(
        androidIcon: switch (repeat) {
          AudioServiceRepeatMode.one => 'drawable/ic_auto_repeat_one_on',
          AudioServiceRepeatMode.all => 'drawable/ic_auto_repeat_on',
          _ => 'drawable/ic_auto_repeat',
        },
        label: switch (repeat) {
          AudioServiceRepeatMode.one => 'Repeat one',
          AudioServiceRepeatMode.all => 'Repeat all',
          _ => 'Repeat off',
        },
        name: 'repeat',
      ));
    }
    if (favorite != null) {
      // Heart on the now-playing screen; toggles the Jellyfin favorite.
      controls.add(MediaControl.custom(
        androidIcon: favorite
            ? 'drawable/ic_auto_favorite'
            : 'drawable/ic_auto_favorite_border',
        label: 'Favorite',
        name: 'favorite',
      ));
    }
    playbackState.add(PlaybackState(
      controls: controls,
      // Search + play-from-id are always available (so the car's search button
      // works in every mode); seeking only when it's a seekable track.
      systemActions: radio
          ? const {
              MediaAction.playFromSearch,
              MediaAction.playFromMediaId,
            }
          : const {
              MediaAction.playFromSearch,
              MediaAction.playFromMediaId,
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
      androidCompactActionIndices: radio ? const [0] : const [0, 1, 2],
      processingState:
          buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: buffered,
      speed: speed,
      shuffleMode:
          shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: repeat,
      queueIndex: queueIndex,
    ));
  }
}

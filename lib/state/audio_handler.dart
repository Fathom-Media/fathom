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

  /// Publish the current track's metadata for the notification/lock screen.
  void setNowPlaying(MediaItem item) => mediaItem.add(item);

  /// Publish transport state (playing/paused, position, buffered) so the
  /// notification's controls and scrubber reflect the player.
  void setPlayback({
    required bool playing,
    required bool buffering,
    required Duration position,
    required Duration buffered,
    double speed = 1.0,
  }) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState:
          buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: buffered,
      speed: speed,
    ));
  }
}

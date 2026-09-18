import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

enum SleepMode { off, timed, endOfItem }

@immutable
class SleepTimerState {
  const SleepTimerState({this.mode = SleepMode.off, this.endsAt});
  final SleepMode mode;

  /// When a timed stop happens (null unless [mode] is [SleepMode.timed]).
  final DateTime? endsAt;

  bool get active => mode != SleepMode.off;
}

/// Something playing that the timer can wind down: fade its sound out over the
/// given time, then pause. Registered by each player while it's open.
typedef SleepTarget = Future<void> Function(Duration fade);

/// The sleep timer: stop playback after a set time (fading out gently), or at
/// the end of the current track or episode instead of moving on to the next.
///
/// One app-wide timer rather than one per player, so setting it from Now
/// Playing and then opening a video still stops whatever is playing when it
/// runs out. Session-only: it isn't remembered across launches.
class SleepTimerController extends Notifier<SleepTimerState> {
  static const fade = Duration(seconds: 15);

  final Set<SleepTarget> _targets = {};
  Timer? _timer;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SleepTimerState();
  }

  /// Registers a player for timed stops; call the returned function to
  /// unregister (e.g. from dispose).
  VoidCallback register(SleepTarget target) {
    _targets.add(target);
    return () => _targets.remove(target);
  }

  void startTimed(Duration duration) {
    _timer?.cancel();
    state = SleepTimerState(
        mode: SleepMode.timed, endsAt: DateTime.now().add(duration));
    // Start fading early so playback reaches silence right as time runs out.
    final untilFade = duration > fade ? duration - fade : Duration.zero;
    _timer = Timer(untilFade, _windDown);
  }

  void startEndOfItem() {
    _timer?.cancel();
    state = const SleepTimerState(mode: SleepMode.endOfItem);
  }

  void cancel() {
    _timer?.cancel();
    state = const SleepTimerState();
  }

  /// For a player that just reached the end of its track or episode: true
  /// (and the timer is done) when it should stop there instead of moving on.
  bool consumeEndOfItem() {
    if (state.mode != SleepMode.endOfItem) return false;
    cancel();
    return true;
  }

  bool get stopsAtEndOfItem => state.mode == SleepMode.endOfItem;

  Future<void> _windDown() async {
    final remaining = state.endsAt?.difference(DateTime.now()) ?? Duration.zero;
    final fadeFor = remaining < fade ? remaining : fade;
    state = const SleepTimerState();
    await Future.wait([
      for (final t in _targets.toList())
        t(fadeFor).catchError((Object _) {}),
    ]);
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerController, SleepTimerState>(
        SleepTimerController.new);

/// Fades a media_kit [player] to silence over [fade], pauses it, and puts the
/// volume back so the next play isn't silent. Steps faster than VolumeSync's
/// save debounce, so the passing levels are never stored as the remembered
/// volume; only the restored one is. Stops fading (and restores) if playback is
/// paused by someone else along the way.
Future<void> fadeOutAndPause(Player player, Duration fade) async {
  if (!player.state.playing) return;
  final start = player.state.volume;
  const stepEvery = Duration(milliseconds: 250);
  final steps = (fade.inMilliseconds / stepEvery.inMilliseconds).ceil();
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(stepEvery);
    if (!player.state.playing) break;
    await player.setVolume(start * (1 - i / steps));
  }
  await player.pause();
  await player.setVolume(start);
}

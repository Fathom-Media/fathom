import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Keeps a player's volume tied to the one the app remembers.
///
/// Every player uses this rather than each screen rolling its own: three copies
/// of "restore, then save on change" would drift, and a volume that sticks in
/// two players out of three is worse than one that sticks in none — it reads as
/// a bug rather than a missing feature.
///
/// Deliberately knows nothing about Riverpod: it takes a getter and a setter,
/// so it can be tested against a plain variable.
class VolumeSync {
  VolumeSync({
    required this.player,
    required this.read,
    required this.write,
  });

  final Player player;

  /// The remembered volume, 0-100.
  final double Function() read;

  /// Stores a new volume. Called at most once per gesture, not per frame.
  final void Function(double) write;

  StreamSubscription<double>? _sub;
  Timer? _debounce;

  /// The last value seen, so the echo of our own setVolume isn't written back
  /// as though the viewer had chosen it.
  double? _lastSeen;

  /// Re-reads the remembered volume and applies it to the player. Use when the
  /// stored value wasn't available at [attach] time (e.g. preferences loaded
  /// asynchronously after the player was created) so the player would otherwise
  /// be stuck at its default while the UI shows the remembered level.
  void reapply() {
    final stored = read().clamp(0.0, 100.0);
    _lastSeen = stored;
    unawaited(player.setVolume(stored));
  }

  /// Applies the remembered volume, then keeps it up to date.
  void attach() {
    final stored = read().clamp(0.0, 100.0);
    _lastSeen = stored;
    unawaited(player.setVolume(stored));

    _sub = player.stream.volume.listen((v) {
      // Mute is volume 0 here, and isn't remembered on purpose: a run that
      // ended muted starts audible at the last real level, because coming back
      // to silence reads as broken rather than as remembered.
      if (v <= 0) return;
      if (_lastSeen != null && (v - _lastSeen!).abs() < 0.5) return;
      _lastSeen = v;

      // Dragging the slider emits a value per frame. Writing each one would
      // hammer storage for a gesture with a single meaningful result.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => write(v));
    });
  }

  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
  }
}

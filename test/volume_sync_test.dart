import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:fathom/state/volume_sync.dart';

void main() {
  setUpAll(MediaKit.ensureInitialized);

  late Player player;
  late double stored;
  late List<double> writes;
  late VolumeSync sync;

  setUp(() {
    player = Player();
    stored = 100;
    writes = [];
    sync = VolumeSync(
      player: player,
      read: () => stored,
      write: (v) {
        stored = v;
        writes.add(v);
      },
    );
  });

  tearDown(() async {
    sync.dispose();
    await player.dispose();
  });

  test('applies the remembered volume on attach', () async {
    stored = 35;
    sync.attach();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.state.volume, closeTo(35, 0.6));
  });

  test('a change is written once, after the gesture settles', () async {
    sync.attach();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // A slider drag: many values, one intent.
    for (final v in [90.0, 80.0, 70.0, 60.0, 55.0]) {
      await player.setVolume(v);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(writes, hasLength(1), reason: 'debounced to one write per gesture');
    expect(writes.single, closeTo(55, 0.6));
    expect(stored, closeTo(55, 0.6));
  });

  test('muting is not remembered', () async {
    stored = 40;
    sync.attach();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await player.setVolume(0); // mute
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // Coming back to a silent app reads as broken, so 0 is never stored.
    expect(stored, closeTo(40, 0.6));
    expect(writes, isEmpty);
  });

  test('restoring does not write the value straight back', () async {
    // attach() sets the volume, which echoes on the stream. Saving that echo
    // would be a pointless write on every single player open.
    stored = 60;
    sync.attach();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(writes, isEmpty);
  });

  test('a corrupt stored value cannot silence or deafen', () async {
    stored = 900;
    sync.attach();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.state.volume, lessThanOrEqualTo(100));
  });
}

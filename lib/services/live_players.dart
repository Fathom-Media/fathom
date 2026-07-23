import 'package:media_kit/media_kit.dart';

/// Every mpv player currently alive, so they can be torn down in a defined
/// order before the process exits.
///
/// media_kit's video output holds GL resources that it releases through the
/// Flutter engine. At process exit the engine is torn down first, and mpv then
/// unregisters its texture against an engine that is already gone — which is
/// the FlutterEngineRemoveView(kInvalidArguments) + GLib criticals + 'corrupted
/// double-linked list' crash on close.
///
/// Screens dispose their own player when they leave the tree; this only covers
/// the case nothing else does — quitting with playback still live. The app-wide
/// audio player is the clearest example: it hangs off a root provider whose
/// onDispose never runs, because nothing disposes the root container at exit.
class LivePlayers {
  LivePlayers._();

  static final Set<Player> _players = <Player>{};

  static void add(Player player) => _players.add(player);

  static void remove(Player player) => _players.remove(player);

  /// Stops and disposes every live player. Safe to call more than once, and
  /// deliberately swallows errors: this runs while the app is quitting, and a
  /// throw here would abort the remaining teardown and cause the very crash it
  /// exists to avoid.
  static Future<void> disposeAll() async {
    final players = _players.toList();
    _players.clear();
    for (final player in players) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}

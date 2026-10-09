import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/interface_scale.dart';
import 'preferences.dart';

const _display = MethodChannel('app.fathom.player/display');

/// Whether Interface Size applies: desktop only. Android and Android TV have
/// their own display size settings, and the TV layout is built for the couch.
bool get interfaceScaleSupported =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

/// Asks the Linux runner about the monitor Fathom is on and works out the
/// automatic interface size for it (see [autoInterfaceScale]). 1.0 everywhere
/// else: Windows scales per monitor by itself, fractions included, which GTK
/// on Linux can't.
Future<double> queryAutoInterfaceScale() async {
  if (!Platform.isLinux) return 1.0;
  try {
    final m = await _display.invokeMapMethod<String, Object?>('density');
    if (m == null) return 1.0;
    return autoInterfaceScale(
      widthPx: (m['widthPx'] as int?) ?? 0,
      widthMm: (m['widthMm'] as int?) ?? 0,
      systemScale: (m['scale'] as int?) ?? 1,
    );
  } catch (_) {
    return 1.0;
  }
}

/// The automatic interface size for the monitor Fathom is on. Seeded before
/// the first frame (main() sets [initial]) so the window never opens at one
/// size and jumps to another; [refresh] re-checks after the window moves,
/// since it may now be on a different monitor.
class AutoInterfaceScale extends Notifier<double> {
  static double initial = 1.0;

  @override
  double build() => initial;

  Future<void> refresh() async {
    final next = await queryAutoInterfaceScale();
    if (next != state) state = next;
  }
}

final autoInterfaceScaleProvider =
    NotifierProvider<AutoInterfaceScale, double>(AutoInterfaceScale.new);

/// The interface size in effect: the one chosen in settings, else automatic.
final interfaceScaleProvider = Provider<double>((ref) {
  if (!interfaceScaleSupported) return 1.0;
  final chosen = ref.watch(preferencesProvider).asData?.value.interfaceScale ?? 0;
  if (chosen > 0) return chosen;
  return ref.watch(autoInterfaceScaleProvider);
});

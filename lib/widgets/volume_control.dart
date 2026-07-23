import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/preferences.dart';

IconData volumeIcon(double v) => v <= 0
    ? Icons.volume_off_rounded
    : v < 45
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

/// Volume row (mute toggle + slider) bound to the app's shared volume. Dragging
/// sets the player, which persists through VolumeSync, so the level is the same
/// across the music player, the video player and YouTube.
class VolumeSlider extends ConsumerStatefulWidget {
  final Player player;
  const VolumeSlider({super.key, required this.player});

  @override
  ConsumerState<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<VolumeSlider> {
  double? _value;
  bool _dragging = false;
  double _beforeMute = 100;

  void _set(double v) {
    setState(() => _value = v);
    widget.player.setVolume(v);
  }

  @override
  Widget build(BuildContext context) {
    // Keep in step with the volume changed elsewhere (video/YouTube), but not
    // while the user is dragging this slider.
    ref.listen(preferencesProvider, (_, next) {
      final v = next.asData?.value.volume;
      if (v != null && !_dragging && mounted && v != _value) {
        setState(() => _value = v);
      }
    });
    final v =
        (_value ?? ref.read(preferencesProvider).asData?.value.volume ?? 100)
            .clamp(0.0, 100.0);
    return Row(
      children: [
        IconButton(
          icon: Icon(volumeIcon(v)),
          tooltip: v <= 0
              ? AppLocalizations.of(context).playerUnmute
              : AppLocalizations.of(context).playerMute,
          onPressed: () {
            if (v > 0) {
              _beforeMute = v;
              _set(0);
            } else {
              _set(_beforeMute <= 0 ? 100 : _beforeMute);
            }
          },
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: v,
              max: 100,
              onChangeStart: (_) => _dragging = true,
              onChanged: _set,
              onChangeEnd: (_) => _dragging = false,
            ),
          ),
        ),
      ],
    );
  }
}

/// A volume icon that opens the [VolumeSlider] in a small popover, for tight
/// spaces like the mini player.
class VolumeMenuButton extends ConsumerWidget {
  final Player player;
  const VolumeMenuButton({super.key, required this.player});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(preferencesProvider).asData?.value.volume ?? 100;
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        icon: Icon(volumeIcon(v)),
        tooltip: AppLocalizations.of(context).playerVolume,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: VolumeSlider(player: player),
          ),
        ),
      ],
    );
  }
}

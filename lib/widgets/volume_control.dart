import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/cast.dart';
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
    // While casting, the slider drives the cast device's volume (like every
    // other casting app); otherwise it's the local player.
    if (ref.read(castControllerProvider).casting) {
      setState(() => _value = v);
      ref.read(castControllerProvider.notifier).setVolume(v);
    } else {
      setState(() => _value = v);
      widget.player.setVolume(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castControllerProvider);
    final casting = cast.casting;
    // Keep in step with the volume changed elsewhere (video/YouTube), but not
    // while the user is dragging this slider or driving a cast device.
    ref.listen(preferencesProvider, (_, next) {
      final v = next.asData?.value.volume;
      if (!casting && v != null && !_dragging && mounted && v != _value) {
        setState(() => _value = v);
      }
    });
    final v = (casting
            ? cast.volume
            : (_value ?? ref.read(preferencesProvider).asData?.value.volume ?? 100))
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

/// Volume as a speaker icon that reveals a horizontal slider *inline* — the
/// slider eases open to the right of the icon on hover (desktop) or a tap
/// (touch), YouTube-style, instead of a detached popover. Bound to the shared
/// app volume (cast-aware), so it stays in step with the other players. Used on
/// the full now-playing screens, which have the room; the cramped mini player
/// keeps [VolumeMenuButton].
class InlineVolume extends ConsumerStatefulWidget {
  final Player player;

  /// Expand the slider to the LEFT of the speaker (the icon stays put on the
  /// right). Use when the control is anchored to a right edge so the expanded
  /// slider grows inward; the default expands to the right.
  final bool expandLeft;
  const InlineVolume({super.key, required this.player, this.expandLeft = false});

  @override
  ConsumerState<InlineVolume> createState() => _InlineVolumeState();
}

class _InlineVolumeState extends ConsumerState<InlineVolume> {
  bool _open = false;
  bool _dragging = false;
  double? _value;
  double _beforeMute = 100;
  Timer? _closeTimer;

  static const _sliderWidth = 128.0;

  // Touch has no hover, so there it's tap-to-toggle; on desktop, hover reveals
  // the slider and a click mutes (the usual split).
  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  // Touch only: collapse a short beat after the last interaction, so the pill
  // doesn't linger over the controls until you tap the icon again.
  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _open = false);
    });
  }

  void _set(double v) {
    if (ref.read(castControllerProvider).casting) {
      setState(() => _value = v);
      ref.read(castControllerProvider.notifier).setVolume(v);
    } else {
      setState(() => _value = v);
      widget.player.setVolume(v);
    }
  }

  void _toggleMute(double v) {
    if (v > 0) {
      _beforeMute = v;
      _set(0);
    } else {
      _set(_beforeMute <= 0 ? 100 : _beforeMute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cast = ref.watch(castControllerProvider);
    final casting = cast.casting;
    ref.listen(preferencesProvider, (_, next) {
      final v = next.asData?.value.volume;
      if (!casting && v != null && !_dragging && mounted && v != _value) {
        setState(() => _value = v);
      }
    });
    final v = (casting
            ? cast.volume
            : (_value ??
                ref.read(preferencesProvider).asData?.value.volume ??
                100))
        .clamp(0.0, 100.0);

    final iconBtn = IconButton(
      icon: Icon(volumeIcon(v)),
      tooltip: v <= 0 ? l.playerUnmute : l.playerMute,
      onPressed: () {
        if (_touch) {
          setState(() => _open = !_open);
          if (_open) {
            _scheduleClose();
          } else {
            _closeTimer?.cancel();
          }
        } else {
          _toggleMute(v);
        }
      },
    );
    // The slider wipes open under a ClipRect via an Align width-factor (0→1), so
    // it reveals cleanly without reparenting the render object (an OverflowBox
    // here tripped a 'child._parent == this' assertion). It anchors on the icon
    // side — right edge when expanding left — and grows outward.
    final reveal = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _open ? 1 : 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment:
              widget.expandLeft ? Alignment.centerRight : Alignment.centerLeft,
          widthFactor: t,
          child: child,
        ),
      ),
      child: SizedBox(
        width: _sliderWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: v,
              max: 100,
              onChangeStart: (_) {
                _dragging = true;
                _closeTimer?.cancel(); // hold open while adjusting
              },
              onChanged: _set,
              onChangeEnd: (_) {
                _dragging = false;
                if (_touch && _open) _scheduleClose();
              },
            ),
          ),
        ),
      ),
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: widget.expandLeft ? [reveal, iconBtn] : [iconBtn, reveal],
    );
    // When open, the icon + slider sit on a soft floating pill (like the mini
    // player's popover) so the slider reads as its own surface rather than a
    // bare bar laid over whatever's behind it — e.g. the music transport on a
    // narrow phone. The surface fades in with the reveal; collapsed it's nothing
    // but the speaker icon.
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _open
            ? const Color(0xFF16151A).withValues(alpha: 0.94)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        boxShadow: _open
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: row,
    );

    if (_touch) return chip;
    return MouseRegion(
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) {
        if (!_dragging) setState(() => _open = false);
      },
      child: chip,
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

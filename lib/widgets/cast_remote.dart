import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/cast.dart';
import '../state/library_providers.dart';

/// Full-screen "now casting" remote shown over the video while a cast session is
/// live: the title's artwork behind, the device name, a scrubber and play/pause
/// (plus optional episode skip) that drive the receiver, and a Stop button. The
/// TV plays; the phone is the remote, as YouTube/Netflix/Plex do it.
class CastRemote extends ConsumerStatefulWidget {
  final String? artworkUrl;
  final String? title;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const CastRemote({
    super.key,
    this.artworkUrl,
    this.title,
    this.onPrevious,
    this.onNext,
  });

  @override
  ConsumerState<CastRemote> createState() => _CastRemoteState();
}

class _CastRemoteState extends ConsumerState<CastRemote> {
  double? _drag;

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cast = ref.watch(castControllerProvider);
    final ctrl = ref.read(castControllerProvider.notifier);
    final maxMs = cast.durationMs.toDouble();
    final posMs =
        maxMs <= 0 ? 0.0 : cast.positionMs.toDouble().clamp(0.0, maxMs);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred, dimmed artwork behind the controls (Plex/Netflix style).
        if (widget.artworkUrl != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Image.network(
              widget.artworkUrl!,
              fit: BoxFit.cover,
              headers: ref.watch(imageHeadersProvider),
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),
          ),
        const ColoredBox(color: Color(0xB3000000)),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    cast.connected
                        ? Icons.cast_connected_rounded
                        : Icons.cast_rounded,
                    size: 48,
                    color: Colors.white),
                const SizedBox(height: 14),
                if (widget.title != null)
                  Text(widget.title!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  cast.connected
                      ? l.castConnectedTo(cast.deviceName ?? '')
                      : l.castConnecting(cast.deviceName ?? ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                if (cast.connected) ...[
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs <= 0 ? 1 : maxMs,
                      value: _drag ?? (maxMs <= 0 ? 0 : posMs),
                      onChanged:
                          maxMs <= 0 ? null : (v) => setState(() => _drag = v),
                      onChangeEnd: (v) {
                        ctrl.seek(v.round());
                        setState(() => _drag = null);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(Duration(milliseconds: cast.positionMs)),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        Text(_fmt(Duration(milliseconds: cast.durationMs)),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.onPrevious != null)
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: widget.onPrevious,
                        ),
                      IconButton(
                        iconSize: 56,
                        color: Colors.white,
                        icon: Icon(cast.playing
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded),
                        onPressed: () =>
                            cast.playing ? ctrl.pause() : ctrl.play(),
                      ),
                      if (widget.onNext != null)
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: widget.onNext,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: ctrl.endSession,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(l.castStop),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

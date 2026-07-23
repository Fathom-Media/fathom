import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A light, animated caustic shimmer drawn as an additive overlay, evoking
/// underwater light playing over whatever sits beneath it. It fills its parent,
/// so wrap it in a Positioned.fill over the content you want it to wash across.
/// Renders nothing until (or if never) the shader loads, leaving the content
/// untouched, so it can only ever add, not break.
class WaterShimmer extends StatefulWidget {
  const WaterShimmer({super.key});

  @override
  State<WaterShimmer> createState() => _WaterShimmerState();
}

class _WaterShimmerState extends State<WaterShimmer>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/ripple.frag');
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _ticker.start();
    } catch (_) {
      // Leave _shader null so build() renders nothing.
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return const SizedBox.shrink();
    return CustomPaint(
      size: Size.infinite,
      painter: _ShimmerPainter(shader, _time),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ValueListenable<double> time;

  _ShimmerPainter(this.shader, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) =>
      oldDelegate.shader != shader;
}

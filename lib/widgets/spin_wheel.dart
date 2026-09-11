import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../models/base_item.dart';
import '../services/diagnostics.dart';
import 'media_image.dart';

/// A Price-Is-Right-style prize wheel: N labeled wedges, a fixed pointer at
/// the top, and a spin that decelerates into a landing with a peg-tick as
/// each wedge boundary passes. The outcome is chosen before the animation
/// starts (there's no physical randomness to simulate), the deceleration
/// curve just makes a predetermined stop feel like real momentum and
/// friction rather than a snap decision.
class SpinWheel extends StatefulWidget {
  final List<BaseItemDto> items;
  final double size;

  /// Called once the wheel has fully stopped, with the index into [items]
  /// the pointer landed on.
  final ValueChanged<int> onLanded;

  const SpinWheel({
    super.key,
    required this.items,
    required this.onLanded,
    this.size = 320,
  });

  @override
  State<SpinWheel> createState() => SpinWheelState();
}

class SpinWheelState extends State<SpinWheel> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _rotation;
  int _lastSegment = -1;
  bool _spinning = false;
  final _random = math.Random();

  // A short, independent flap each time a peg passes under the pointer, like
  // a real spring-loaded flapper getting knocked up and snapping back, not
  // just a static triangle.
  late final AnimationController _flapController;
  late final Animation<double> _flap;

  // A continuously-flipping hourglass in the center hub while the wheel is
  // spinning, like sand actually falling and the glass getting turned over,
  // rather than a static icon.
  late final AnimationController _hourglassController;

  // The peg-tick sound. Reuses media_kit (already a dependency everywhere
  // else in the app) rather than adding a new audio package just for this.
  // Opened once and re-seeked/replayed per tick, not re-opened each time,
  // so rapid ticks early in a fast spin don't each pay demuxer setup cost.
  late final Player _tickPlayer;
  // Guards against seeking/playing before the asset has actually finished
  // loading: media_kit's seek()/play() don't throw or no-op visibly if
  // there's no media loaded yet, so an early command is silently lost
  // rather than surfaced as an error.
  bool _tickReady = false;

  // A fixed, high-contrast palette cycled across wedges, independent of the
  // theme accent so every wedge reads clearly against its neighbours.
  static const _palette = [
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _flapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    // Knocked up fast, springs back past rest and settles, like a real
    // spring-loaded flapper rather than a linear snap.
    _flap = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -0.45)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.45, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 65,
      ),
    ]).animate(_flapController);
    _hourglassController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _tickPlayer = Player();
    unawaited(_loadTickSound());
  }

  // A plain async function, not a bare .then()/.catchError() chain: Media's
  // constructor resolves and validates the asset path synchronously, so a
  // missing/misbundled asset throws before .open() is even called and
  // before any .catchError() on its result could ever see it. Wrapping the
  // whole thing in async turns that synchronous throw into a normal Future
  // error this try/catch actually catches.
  Future<void> _loadTickSound() async {
    Diagnostics.instance.add('wheel', 'tick sound: opening asset');
    try {
      await _tickPlayer.open(
        Media('asset:///assets/audio/wheel_tick.wav'),
        play: false,
      );
      _tickReady = true;
      Diagnostics.instance.add('wheel',
          'tick sound: opened, duration=${_tickPlayer.state.duration} volume=${_tickPlayer.state.volume}');
    } catch (e) {
      Diagnostics.instance.add('wheel', 'tick sound: failed to open: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _flapController.dispose();
    _hourglassController.dispose();
    _tickPlayer.dispose();
    super.dispose();
  }

  double get _segmentAngle => (2 * math.pi) / widget.items.length;

  /// Which wedge is currently under the fixed top pointer, for a given
  /// wheel rotation [theta] (radians, how far the wheel has turned).
  int _segmentAt(double theta) {
    const pointerAngle = -math.pi / 2; // top, in canvas angle convention
    var originalAngle = (pointerAngle - theta) % (2 * math.pi);
    if (originalAngle < 0) originalAngle += 2 * math.pi;
    final seg = _segmentAngle;
    return (originalAngle / seg).floor() % widget.items.length;
  }

  bool get isSpinning => _spinning;

  /// Spins to a random wedge, several full turns first for effect. Ticks a
  /// selection haptic on every wedge boundary crossed along the way.
  Future<void> spin() async {
    if (_spinning || widget.items.length < 2) return;
    setState(() => _spinning = true);
    _hourglassController.repeat();
    final targetIndex = _random.nextInt(widget.items.length);
    final seg = _segmentAngle;
    // Land somewhere within the middle 70% of the wedge, not dead-center
    // every time and never right on a boundary.
    final jitter = (_random.nextDouble() - 0.5) * seg * 0.7;
    final targetOriginalAngle = targetIndex * seg + seg / 2 + jitter;
    const pointerAngle = -math.pi / 2;
    var base = pointerAngle - targetOriginalAngle;
    base = base % (2 * math.pi);
    if (base < 0) base += 2 * math.pi;
    // More turns alongside the longer duration so the opening speed stays
    // just as fast and the extra time lands in the slow, suspenseful crawl.
    final spins = 9 + _random.nextInt(3); // 9-11 extra full turns
    final target = base + 2 * math.pi * spins;

    _lastSegment = _segmentAt(0);
    _controller.duration =
        Duration(milliseconds: 7000 + _random.nextInt(1000));
    _rotation = Tween<double>(begin: 0, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuint),
    );
    _rotation.addListener(_onTick);
    _controller.reset();
    await _controller.forward();
    _rotation.removeListener(_onTick);
    _hourglassController.stop();
    _hourglassController.reset();
    if (!mounted) return;
    setState(() => _spinning = false);
    HapticFeedback.mediumImpact();
    widget.onLanded(targetIndex);
  }

  void _onTick() {
    final v = _rotation.value;
    final seg = _segmentAt(v);
    if (seg != _lastSegment) {
      _lastSegment = seg;
      HapticFeedback.selectionClick();
      _flapController.forward(from: 0);
      unawaited(_playTick());
    }
  }

  Future<void> _playTick() async {
    // Skip rather than queue: a command sent before the asset has loaded
    // is silently dropped anyway, and catching up on several queued clicks
    // in a burst once ready would sound worse than just missing a couple
    // of the earliest, fastest pegs.
    if (!_tickReady) {
      Diagnostics.instance.add('wheel', 'tick: skipped, player not ready yet');
      return;
    }
    try {
      await _tickPlayer.seek(Duration.zero);
      await _tickPlayer.play();
      // media_kit's seek()/play() can report success with playing=true even
      // when nothing audible actually happens, so log the resulting state
      // unconditionally rather than only on a thrown exception.
      Diagnostics.instance.add('wheel',
          'tick: played, playing=${_tickPlayer.state.playing} pos=${_tickPlayer.state.position} vol=${_tickPlayer.state.volume}');
    } catch (e) {
      Diagnostics.instance.add('wheel', 'tick: playback failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return GestureDetector(
      onTap: _spinning ? null : spin,
      child: SizedBox(
        width: widget.size,
        height: widget.size + 24,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 24,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final theta =
                      _controller.isAnimating || _controller.value > 0
                          ? _rotation.value
                          : 0.0;
                  return Transform.rotate(angle: theta, child: child);
                },
                child: ClipOval(
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Stack(
                      children: [
                        // Palette fill first, as the fallback behind each
                        // poster (visible at the wedge's far corners a
                        // poster image doesn't quite reach, and while it's
                        // still loading).
                        CustomPaint(
                          size: Size.square(widget.size),
                          painter: _WheelFillPainter(count: n, palette: _palette),
                        ),
                        for (var i = 0; i < n; i++)
                          Positioned.fill(
                            child: ClipPath(
                              clipper: _WedgeClipper(index: i, count: n),
                              // A fresh Stack so the poster's own Positioned
                              // (sized/placed in full-wheel coordinates) has
                              // a direct Stack ancestor, with only this
                              // clip's own Positioned.fill wrapping it.
                              child: Stack(
                                children: [
                                  _WedgePoster(
                                    item: widget.items[i],
                                    index: i,
                                    count: n,
                                    wheelSize: widget.size,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // A center-to-rim darkening so the title text and the
                        // divider/peg lines stay legible over busy poster art.
                        IgnorePointer(
                          child: Container(
                            width: widget.size,
                            height: widget.size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.05),
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Dividers, rim, and pegs on top of the poster art so
                        // they stay crisp regardless of what's underneath.
                        CustomPaint(
                          size: Size.square(widget.size),
                          painter: _WheelLinesPainter(count: n),
                        ),
                        for (var i = 0; i < n; i++)
                          _WedgeTitle(
                            item: widget.items[i],
                            index: i,
                            count: n,
                            wheelSize: widget.size,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Fixed pointer, doesn't rotate with the wheel; flaps on its own
            // short animation each time a peg passes under it.
            Positioned(
              top: 0,
              child: _Pointer(flap: _flap),
            ),
            // Center hub, also the tap target.
            Positioned(
              top: 24 + widget.size / 2 - 34,
              child: _Hub(spinning: _spinning, hourglass: _hourglassController),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pointer extends StatelessWidget {
  final Animation<double> flap;
  const _Pointer({required this.flap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flap,
      builder: (context, child) => Transform.rotate(
        // Pivots from the top, like it's hinged there, instead of spinning
        // around its own center.
        alignment: Alignment.topCenter,
        angle: flap.value,
        child: child,
      ),
      child: CustomPaint(
        size: const Size(28, 30),
        painter: _PointerPainter(),
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD54A)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, paint);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Hub extends StatelessWidget {
  final bool spinning;
  final Animation<double> hourglass;
  const _Hub({required this.spinning, required this.hourglass});

  static const _sand = Color(0xFFFFD54A);

  BoxDecoration _decoration({double glow = 0}) => BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF16151A),
        border: Border.all(
          color: Color.lerp(Colors.white24, _sand, glow * 0.8)!,
          width: 3,
        ),
        boxShadow: [
          const BoxShadow(
              color: Colors.black54, blurRadius: 10, offset: Offset(0, 3)),
          if (glow > 0)
            BoxShadow(
              color: _sand.withValues(alpha: 0.18 + 0.32 * glow),
              blurRadius: 14 + 12 * glow,
              spreadRadius: 1 + 3 * glow,
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (!spinning) {
      return Container(
        width: 68,
        height: 68,
        decoration: _decoration(),
        alignment: Alignment.center,
        child: const Icon(Icons.casino_rounded, color: Colors.white, size: 28),
      );
    }
    return AnimatedBuilder(
      animation: hourglass,
      builder: (context, _) {
        // One loop is a real hourglass cycle: the sand runs from the top
        // bulb to the bottom (a smooth crossfade top -> both -> bottom),
        // then the glass is turned over. A bottom-filled hourglass rotated
        // 180deg IS a top-filled one, so the loop restarts seamlessly.
        final t = hourglass.value;
        const runEnd = 0.7;
        var angle = 0.0;
        var scale = 1.0;
        double top, full, bottom;
        if (t < runEnd) {
          final p = Curves.easeInOut.transform(t / runEnd);
          top = (1 - p * 2).clamp(0.0, 1.0);
          bottom = (p * 2 - 1).clamp(0.0, 1.0);
          full = 1 - top - bottom;
        } else {
          final p = (t - runEnd) / (1 - runEnd);
          angle = Curves.easeInOutCubic.transform(p) * math.pi;
          scale = 1 + 0.18 * math.sin(p * math.pi);
          top = 0;
          full = 0;
          bottom = 1;
        }
        // The rim glow breathes once per cycle, brightest mid-flip.
        final glow = 0.5 + 0.5 * math.cos(2 * math.pi * (t - 0.85));
        Widget layer(IconData icon, double opacity) => Opacity(
              opacity: opacity,
              child: Icon(icon, color: _sand, size: 30),
            );
        return Container(
          width: 68,
          height: 68,
          decoration: _decoration(glow: glow),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (top > 0) layer(Icons.hourglass_top_rounded, top),
                  if (full > 0) layer(Icons.hourglass_full_rounded, full),
                  if (bottom > 0) layer(Icons.hourglass_bottom_rounded, bottom),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Flat palette fill per wedge, painted first as the fallback behind each
/// poster: visible at the corners a (deliberately oversized, but not
/// infinite) poster image doesn't quite reach, and while it's still loading.
class _WheelFillPainter extends CustomPainter {
  final int count;
  final List<Color> palette;
  const _WheelFillPainter({required this.count, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final seg = (2 * math.pi) / count;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * seg,
        seg,
        true,
        Paint()
          ..color = palette[i % palette.length]
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelFillPainter oldDelegate) =>
      oldDelegate.count != count;
}

/// Dividers, rim, and pegs, painted last (on top of the poster art) so they
/// stay crisp and readable regardless of what's underneath.
class _WheelLinesPainter extends CustomPainter {
  final int count;
  const _WheelLinesPainter({required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final seg = (2 * math.pi) / count;

    final divider = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2;
    for (var i = 0; i < count; i++) {
      final a = i * seg;
      canvas.drawLine(
        center,
        center + Offset(math.cos(a), math.sin(a)) * radius,
        divider,
      );
    }

    // Rim as a filled ring path, not a stroked drawCircle: on Impeller a
    // stroked circle past a certain radius renders as a thick opaque band
    // that buried everything painted under it (posters, fill, dividers)
    // while the pegs painted after it stayed visible.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: center, radius: radius))
        ..addOval(Rect.fromCircle(center: center, radius: radius - 4)),
      Paint()..color = const Color(0xFF16151A),
    );
    // Pegs (small notches at each boundary, like a real prize wheel).
    final pegPaint = Paint()..color = const Color(0xFFFFD54A);
    for (var i = 0; i < count; i++) {
      final a = i * seg;
      final p = center + Offset(math.cos(a), math.sin(a)) * (radius - 4);
      canvas.drawCircle(p, 4, pegPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WheelLinesPainter oldDelegate) =>
      oldDelegate.count != count;
}

/// Clips a child to exactly one wedge's pie-slice shape, matching the same
/// arc geometry the painters use, so a poster positioned under it only shows
/// through within its own slice.
class _WedgeClipper extends CustomClipper<Path> {
  final int index;
  final int count;
  const _WedgeClipper({required this.index, required this.count});

  @override
  Path getClip(Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final seg = (2 * math.pi) / count;
    return Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: radius), index * seg, seg, false)
      ..close();
  }

  @override
  bool shouldReclip(covariant _WedgeClipper oldClipper) =>
      oldClipper.index != index || oldClipper.count != count;
}

/// The wedge's poster art, sized generously enough to cover its own slice
/// (fewer, wider wedges need a bigger image to reach every corner) and
/// rotated so "up" in the poster points radially outward, then cropped to
/// the slice by the [_WedgeClipper] wrapping it.
class _WedgePoster extends StatelessWidget {
  final BaseItemDto item;
  final int index;
  final int count;
  final double wheelSize;
  const _WedgePoster({
    required this.item,
    required this.index,
    required this.count,
    required this.wheelSize,
  });

  @override
  Widget build(BuildContext context) {
    final seg = (2 * math.pi) / count;
    final mid = index * seg + seg / 2;
    final radius = wheelSize / 2;
    // The smallest 2:3 poster box that still covers this wedge, so as much of
    // the art as possible shows instead of a zoomed-in slice. In the wedge's
    // own frame (bisector pointing outward) its bounding rect runs from the
    // hub to the rim radially and +-r*sin(seg/2) across (count >= 2 keeps
    // seg/2 <= 90deg, so the far corners never dip behind the hub). The
    // small margin keeps anti-aliased clip edges from showing a hairline.
    final rectW = 2 * radius * math.sin(seg / 2);
    final rectH = radius;
    final boxW = math.max(rectW, rectH * 2 / 3) * 1.04 + 2;
    final boxH = boxW * 1.5;
    final cx = radius + math.cos(mid) * rectH / 2;
    final cy = radius + math.sin(mid) * rectH / 2;
    return Positioned(
      left: cx - boxW / 2,
      top: cy - boxH / 2,
      width: boxW,
      height: boxH,
      child: Transform.rotate(
        angle: mid + math.pi / 2,
        // Without this, MediaImage falls back to a fixed 480px request
        // regardless of the actual box size, so a big wheel stretches a
        // comparatively tiny source image several times over.
        child: MediaImage(
          item: item,
          placeholderIcon: Icons.movie_rounded,
          maxHeight: boxH.round().clamp(480, 1200),
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

/// The wedge's title, sitting near the outer rim over the darkened part of
/// the poster where it reads clearly, rotated to point outward like the
/// poster beneath it.
class _WedgeTitle extends StatelessWidget {
  final BaseItemDto item;
  final int index;
  final int count;
  final double wheelSize;
  const _WedgeTitle({
    required this.item,
    required this.index,
    required this.count,
    required this.wheelSize,
  });

  @override
  Widget build(BuildContext context) {
    final seg = (2 * math.pi) / count;
    final mid = index * seg + seg / 2;
    final radius = wheelSize / 2;
    final labelRadius = radius * 0.78;
    // Fewer wedges means more room, both angularly and for the eye, so the
    // title grows accordingly rather than sitting at one fixed size
    // regardless of whether there are 2 titles on the wheel or 15.
    final fontSize = (12.0 + 36.0 / count).clamp(10.0, 20.0);
    final labelWidth = (60.0 + 260.0 / count).clamp(70.0, 130.0);
    return Positioned(
      left: radius + math.cos(mid) * labelRadius - labelWidth / 2,
      top: radius + math.sin(mid) * labelRadius - fontSize,
      width: labelWidth,
      child: Transform.rotate(
        angle: mid + math.pi / 2,
        child: Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 4),
              Shadow(color: Colors.black87, blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

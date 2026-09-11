import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/diagnostics.dart';
import '../services/tv_mode.dart';
import '../state/watchlist.dart';
import '../theme/app_theme.dart' show kInlineButtonStyle;
import '../widgets/media_image.dart';
import '../widgets/spin_wheel.dart';
import '../widgets/tv_focus.dart';

/// "Can't decide what to watch?" elimination wheel: pick candidates from the
/// Watchlist, spin, the wedge the pointer lands on is eliminated, repeat
/// until one remains. Single-device by design (see the module doc on
/// SpinWheel): whoever's holding the phone/remote spins while everyone else
/// just watches the screen, like passing a real prize wheel around a room,
/// no cross-device sync needed for that.
class MovieWheelScreen extends ConsumerStatefulWidget {
  const MovieWheelScreen({super.key});

  @override
  ConsumerState<MovieWheelScreen> createState() => _MovieWheelScreenState();
}

enum _Phase { setup, spinning, winner }

class _MovieWheelScreenState extends ConsumerState<MovieWheelScreen> {
  _Phase _phase = _Phase.setup;
  final Set<String> _selected = {};
  bool _selectedInit = false;
  List<BaseItemDto> _pool = [];
  BaseItemDto? _justEliminated;
  final _wheelKey = GlobalKey<SpinWheelState>();

  void _initSelection(List<BaseItemDto> watchlist) {
    if (_selectedInit) return;
    _selectedInit = true;
    _selected.addAll(watchlist.map((e) => e.id));
  }

  void _start(List<BaseItemDto> watchlist) {
    setState(() {
      _pool = watchlist.where((e) => _selected.contains(e.id)).toList();
      _phase = _Phase.spinning;
    });
  }

  void _onLanded(int index) {
    setState(() => _justEliminated = _pool[index]);
  }

  void _dismissElimination() {
    setState(() {
      final gone = _justEliminated;
      if (gone != null) _pool = _pool.where((e) => e.id != gone.id).toList();
      _justEliminated = null;
      if (_pool.length == 1) _phase = _Phase.winner;
    });
  }

  void _restart() {
    setState(() {
      _phase = _Phase.setup;
      _pool = [];
      _justEliminated = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final watchlist =
        ref.watch(watchlistProvider).asData?.value ?? const <BaseItemDto>[];
    _initSelection(watchlist);

    return Scaffold(
      appBar: AppBar(title: Text(l.wheelTitle)),
      body: switch (_phase) {
        _Phase.setup => _SetupView(
            watchlist: watchlist,
            selected: _selected,
            onToggle: (id) => setState(() {
              _selected.contains(id)
                  ? _selected.remove(id)
                  : _selected.add(id);
            }),
            onStart: _selected.length >= 2
                ? () => _start(watchlist)
                : null,
          ),
        _Phase.spinning => _SpinView(
            key: ValueKey(_pool.map((e) => e.id).join(',')),
            wheelKey: _wheelKey,
            pool: _pool,
            eliminated: _justEliminated,
            onLanded: _onLanded,
            onDismissElimination: _dismissElimination,
          ),
        _Phase.winner => _WinnerView(
            winner: _pool.first,
            onRestart: _restart,
          ),
      },
    );
  }
}

class _SetupView extends StatelessWidget {
  final List<BaseItemDto> watchlist;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback? onStart;
  const _SetupView({
    required this.watchlist,
    required this.selected,
    required this.onToggle,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (watchlist.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.wheelNeedsWatchlist, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(l.wheelSetupHint,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: watchlist.length,
            itemBuilder: (context, i) {
              final item = watchlist[i];
              final checked = selected.contains(item.id);
              return CheckboxListTile(
                // Lands the remote on real content the moment this phase
                // appears; the global shell autofocus only fires on route
                // changes, and setup/spinning/winner all live in one route.
                autofocus: isTvDevice && i == 0,
                value: checked,
                onChanged: (_) => onToggle(item.id),
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 56,
                    child: MediaImage(item: item, placeholderIcon: Icons.movie_rounded),
                  ),
                ),
                title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.casino_rounded),
              label: Text(selected.length >= 2
                  ? l.wheelStartWith(selected.length)
                  : l.wheelNeedTwo),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpinView extends StatelessWidget {
  final GlobalKey<SpinWheelState> wheelKey;
  final List<BaseItemDto> pool;
  final BaseItemDto? eliminated;
  final ValueChanged<int> onLanded;
  final VoidCallback onDismissElimination;
  const _SpinView({
    super.key,
    required this.wheelKey,
    required this.pool,
    required this.eliminated,
    required this.onLanded,
    required this.onDismissElimination,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l.wheelRemaining(pool.length),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(builder: (context, c) {
                  final size = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) - 48;
                  final wheel = SpinWheel(
                    key: wheelKey,
                    items: pool,
                    size: size.clamp(220.0, 820.0),
                    onLanded: onLanded,
                  );
                  // The wheel's own tap-to-spin is a bare GestureDetector
                  // (mouse/touch only): it has no focus node and isn't part
                  // of D-pad traversal at all, so without this wrap a remote
                  // has no way to ever spin it. TvFocusable is a no-op off TV.
                  return TvFocusable(
                    autofocus: isTvDevice,
                    onTap: () => wheelKey.currentState?.spin(),
                    child: wheel,
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(l.wheelTapToSpin,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
        if (eliminated != null)
          _EliminationOverlay(item: eliminated!, onDone: onDismissElimination),
      ],
    );
  }
}

class _EliminationOverlay extends StatefulWidget {
  final BaseItemDto item;
  final VoidCallback onDone;
  const _EliminationOverlay({required this.item, required this.onDone});

  @override
  State<_EliminationOverlay> createState() => _EliminationOverlayState();
}

class _EliminationOverlayState extends State<_EliminationOverlay> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDone,
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 170,
                  child: Opacity(
                    opacity: 0.5,
                    child: MediaImage(
                        item: widget.item, placeholderIcon: Icons.movie_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.wheelEliminated(widget.item.name),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinnerView extends StatefulWidget {
  final BaseItemDto winner;
  final VoidCallback onRestart;
  const _WinnerView({required this.winner, required this.onRestart});

  @override
  State<_WinnerView> createState() => _WinnerViewState();
}

class _WinnerViewState extends State<_WinnerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final List<_ConfettiPiece> _confetti;
  late final Player _cheerPlayer;

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();
    _confetti = List.generate(70, (_) => _ConfettiPiece(math.Random()));
    HapticFeedback.heavyImpact();
    _cheerPlayer = Player();
    unawaited(_playCheer());
  }

  // A plain async function so a synchronous throw from Media's constructor
  // (it resolves/validates the asset path eagerly, not lazily inside
  // open()) lands as a caught Future error instead of crashing initState.
  Future<void> _playCheer() async {
    try {
      await _cheerPlayer.open(Media('asset:///assets/audio/wheel_winner.wav'));
    } catch (e) {
      Diagnostics.instance.add('wheel', 'winner sound: failed to open: $e');
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _cheerPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.wheelWinnerLabel,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 200,
                    height: 300,
                    child: MediaImage(
                        item: widget.winner, placeholderIcon: Icons.movie_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Text(widget.winner.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      // Same reasoning as the wheel's own autofocus: this
                      // phase change is an internal setState, not a route
                      // change, so the shell's autofocus never refires here.
                      autofocus: isTvDevice,
                      style: kInlineButtonStyle,
                      onPressed: () => context.push('/player', extra: widget.winner),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.commonPlay),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: kInlineButtonStyle,
                      onPressed: widget.onRestart,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l.wheelSpinAgain),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _confettiController,
            builder: (context, _) => CustomPaint(
              painter: _ConfettiPainter(
                  pieces: _confetti, t: _confettiController.value),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

/// One confetti piece's fixed randomized traits, drawn at a position derived
/// purely from the shared clock [t] rather than storing mutable per-frame
/// state, so nothing needs to advance it except the one controller.
class _ConfettiPiece {
  final double x0;
  final double delay;
  final double fallSpeed;
  final double drift;
  final double spin;
  final double phase;
  final double size;
  final Color color;

  _ConfettiPiece(math.Random r)
      : x0 = r.nextDouble(),
        delay = r.nextDouble() * 0.25,
        fallSpeed = 0.8 + r.nextDouble() * 0.5,
        drift = (r.nextDouble() - 0.5) * 0.5,
        spin = (r.nextDouble() - 0.5) * 12,
        phase = r.nextDouble() * math.pi * 2,
        size = 5 + r.nextDouble() * 5,
        color = _kConfettiColors[r.nextInt(_kConfettiColors.length)];
}

const _kConfettiColors = [
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double t;
  const _ConfettiPainter({required this.pieces, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final fall = Curves.easeIn.transform((local * p.fallSpeed).clamp(0.0, 1.0));
      final y = -20 + fall * (size.height + 40);
      final sway = math.sin(local * 4 * math.pi + p.phase) * 18;
      final x = p.x0 * size.width + p.drift * local * size.width + sway;
      final angle = local * p.spin;
      final opacity = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

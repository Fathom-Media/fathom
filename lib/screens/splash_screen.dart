import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../widgets/app_logo.dart';
import '../widgets/water_shimmer.dart';

/// The launch splash: a large logo and the app name over a soft depth wash,
/// shown while the persisted session restores (held a minimum beat by
/// splashReadyProvider so it reads as a branded moment, not a flash).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: DecoratedBox(
        // A deep-sea gradient, independent of the app theme so the branded
        // moment always reads as looking up through dark water: muted teal
        // pooling at the center, near-black abyss at the edges. The caustics and
        // logo sit on top.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.12),
            radius: 1.15,
            colors: [Color(0xFF0C2E3B), Color(0xFF06131B)],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Just the mark (no tile/box); it floats on the deep-sea
                    // gradient so the splash reads as the logo underwater, not
                    // an app icon on a background. The tile stays the launcher
                    // icon.
                    const FathomGlyph(size: 138, color: Color(0xFFEAFBFF)),
                    const SizedBox(height: 26),
                    Text(
                      'Fathom',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.appTagline,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF5BC6DE),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned.fill(child: IgnorePointer(child: WaterShimmer())),
          ],
        ),
      ),
    );
  }
}

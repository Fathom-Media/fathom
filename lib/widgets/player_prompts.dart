import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'tv_focus.dart';

/// Fades its child in once on mount via an explicit controller — robust to
/// parent rebuilds (the exo screen rebuilds every position tick, which reset an
/// implicit TweenAnimationBuilder). Plays once when the element mounts; keeps
/// the element across countdown ticks, so it doesn't re-fade every second.
class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
        child: widget.child,
      );
}

/// Shared Skip Intro / Skip Recap / Skip Credits pill. Built from Material +
/// InkWell with EXPLICIT colours (a bare FilledButton renders invisibly over
/// the video on some GL setups). On TV it scales up for the 10-foot UI and
/// gets a D-pad focus ring.
class SkipPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool tv;

  const SkipPill({
    super.key,
    required this.label,
    required this.onTap,
    this.focusNode,
    this.tv = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = tv ? 1.4 : 1.0;
    Widget pill = Material(
      color: cs.primary,
      shape: const StadiumBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.55),
      child: InkWell(
        customBorder: const StadiumBorder(),
        focusNode: focusNode,
        autofocus: tv,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 13 * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded, size: 22 * s, color: cs.onPrimary),
              SizedBox(width: 8 * s),
              Text(label,
                  style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15 * s,
                      letterSpacing: 0.2)),
            ],
          ),
        ),
      ),
    );
    if (tv) {
      pill = TvFocusRing(
          borderRadius: const BorderRadius.all(Radius.circular(40)), child: pill);
    }
    return _FadeIn(child: pill);
  }
}

/// Shared Up Next prompt shown during the credits of an episode that has a next
/// one. Two presentations chosen by [style]: a poster "card" or a compact
/// Netflix-style "pill" whose accent fills as the countdown runs. [remaining]
/// null means no countdown (a static, click-to-play prompt).
class UpNextPrompt extends StatelessWidget {
  final String style; // 'card' | 'pill'
  final String title;
  final String? subtitle;
  final String? artUrl;
  final Map<String, String>? imageHeaders;
  final int? remaining;
  final int total;
  final VoidCallback onPlayNow;
  final VoidCallback onHide;
  final FocusNode? playFocus;
  final FocusNode? hideFocus;
  final bool tv;

  const UpNextPrompt({
    super.key,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.artUrl,
    required this.imageHeaders,
    required this.remaining,
    required this.total,
    required this.onPlayNow,
    required this.onHide,
    this.playFocus,
    this.hideFocus,
    this.tv = false,
  });

  double get _s => tv ? 1.4 : 1.0;

  @override
  Widget build(BuildContext context) {
    return _FadeIn(
        child: style == 'pill' ? _buildPill(context) : _buildCard(context));
  }

  /// Neutral / accent stadium button used inside the card.
  Widget _button({
    required Color color,
    required Color textColor,
    required String label,
    required VoidCallback onTap,
    FocusNode? focusNode,
    bool autofocus = false,
    IconData? icon,
  }) {
    final s = _s;
    Widget btn = Material(
      color: color,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 11 * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20 * s, color: textColor),
                SizedBox(width: 5 * s),
              ],
              Text(label,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14 * s)),
            ],
          ),
        ),
      ),
    );
    if (tv) {
      btn = TvFocusRing(
          borderRadius: const BorderRadius.all(Radius.circular(40)), child: btn);
    }
    return btn;
  }

  Widget _buildCard(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final s = _s;
    return Material(
      color: const Color(0xF01B1B1F),
      elevation: 10,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 392 * s,
        padding: EdgeInsets.all(12 * s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 116 * s,
                height: 66 * s,
                child: artUrl != null
                    ? Image.network(artUrl!,
                        fit: BoxFit.cover,
                        headers: imageHeaders,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Colors.white10))
                    : const ColoredBox(color: Colors.white10),
              ),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.playerUpNext.toUpperCase(),
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: 11 * s,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 3 * s),
                  if (title.isNotEmpty)
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: 1 * s),
                      child: Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12.5 * s)),
                    ),
                  SizedBox(height: 10 * s),
                  Row(
                    children: [
                      _button(
                        color: cs.primary,
                        textColor: cs.onPrimary,
                        icon: Icons.play_arrow_rounded,
                        label: l.playerUpNextPlayNow,
                        onTap: onPlayNow,
                        focusNode: playFocus,
                        autofocus: tv,
                      ),
                      SizedBox(width: 8 * s),
                      _button(
                        color: Colors.white.withValues(alpha: 0.14),
                        textColor: Colors.white,
                        label: l.playerUpNextHide,
                        onTap: onHide,
                        focusNode: hideFocus,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (remaining != null) ...[
              SizedBox(width: 10 * s),
              SizedBox(
                width: 40 * s,
                height: 40 * s,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 950),
                      curve: Curves.linear,
                      tween: Tween<double>(
                          end: (remaining! / total).clamp(0.0, 1.0)),
                      builder: (_, v, _) => SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: v,
                          strokeWidth: 3.5 * s,
                          color: cs.primary,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    Text('$remaining',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13 * s,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final s = _s;
    final counting = remaining != null;
    final fraction =
        counting ? (1 - remaining! / total).clamp(0.0, 1.0) : 0.0;
    Widget playPill = Material(
      color: counting ? const Color(0xF0202024) : cs.primary,
      shape: const StadiumBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.55),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const StadiumBorder(),
        focusNode: playFocus,
        autofocus: tv,
        onTap: onPlayNow,
        child: Stack(
          children: [
            if (counting)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 950),
                  curve: Curves.linear,
                  tween: Tween<double>(end: fraction),
                  builder: (_, v, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: v,
                      heightFactor: 1,
                      child: ColoredBox(color: cs.primary),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 13 * s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded,
                      size: 22 * s, color: cs.onPrimary),
                  SizedBox(width: 8 * s),
                  Text(l.playerUpNextPlayNow,
                      style: TextStyle(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15 * s,
                          letterSpacing: 0.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (tv) {
      playPill = TvFocusRing(
          borderRadius: const BorderRadius.all(Radius.circular(40)),
          child: playPill);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        playPill,
        SizedBox(width: 8 * s),
        _button(
          color: Colors.black.withValues(alpha: 0.55),
          textColor: Colors.white,
          label: l.playerUpNextHide,
          onTap: onHide,
          focusNode: hideFocus,
        ),
      ],
    );
  }
}

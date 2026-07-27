import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'detail_header.dart';
import 'media_image.dart';
import 'motion.dart';

/// A large auto-rotating hero banner at the top of Home, cycling through a few
/// featured items with their backdrop, title, overview, and quick actions.
///
/// The backdrops live inside a [PageView] (they swipe); the title/overview/
/// buttons are overlaid ONCE in the outer stack — the same bounded stack as the
/// page dots — so they reliably anchor bottom-left regardless of the PageView's
/// internal constraints.
class FeaturedHero extends StatefulWidget {
  final List<BaseItemDto> items;
  const FeaturedHero({super.key, required this.items});

  @override
  State<FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<FeaturedHero> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  // Scroll-driven parallax for the backdrop. A ValueNotifier (not setState) so
  // only the backdrop Transform rebuilds per scroll frame, not the whole hero
  // (PageView + scrims + dots), which was janking Home's scroll.
  ScrollPosition? _scrollPos;
  final _scroll = ValueNotifier<double>(0);

  List<BaseItemDto> get _items => widget.items.take(6).toList();

  @override
  void initState() {
    super.initState();
    _scheduleAdvance();
  }

  /// Arms a one-shot advance 8s out. Re-armed on every page change (see
  /// [_onPageChanged]), so a manual swipe or a dot tap resets the countdown
  /// instead of the carousel jumping right after you interact with it.
  void _scheduleAdvance() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      // Don't spin under reduced motion (stop re-arming rather than waking
      // every 8s to do nothing).
      if (reduceMotion(context)) return;
      if (!_controller.hasClients || _items.length < 2) {
        _scheduleAdvance();
        return;
      }
      final next = (_page + 1) % _items.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    });
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    // Whether the change was a swipe, a dot tap, or the auto-advance, wait a
    // full interval before the next auto move.
    _scheduleAdvance();
  }

  void _goToPage(int i) {
    _controller.animateToPage(i,
        duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
  }

  // Manual drag-to-swipe: scrub the PageView by the pointer delta, clamped so a
  // drag can't overscroll past the ends.
  void _onHeroDragUpdate(DragUpdateDetails d) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    p.jumpTo(
        (p.pixels - d.delta.dx).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  // On release, settle to the nearest page — or the next/previous one if the
  // flick had enough velocity — so it snaps like a real swipe.
  void _onHeroDragEnd(DragEndDetails d) {
    if (!_controller.hasClients) return;
    final page = _controller.page ?? _page.toDouble();
    final v = d.primaryVelocity ?? 0;
    int target;
    if (v <= -300) {
      target = page.ceil();
    } else if (v >= 300) {
      target = page.floor();
    } else {
      target = page.round();
    }
    _controller.animateToPage(target.clamp(0, _items.length - 1),
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _scrollPos) {
      _scrollPos?.removeListener(_onScroll);
      _scrollPos = pos;
      _scrollPos?.addListener(_onScroll);
    }
  }

  void _onScroll() {
    final v = _scrollPos?.pixels ?? 0;
    if ((v - _scroll.value).abs() > 0.5) _scroll.value = v;
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_onScroll);
    _timer?.cancel();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Hold a constant aspect ratio so the crop looks the SAME whether the
    // window is small or maximized (a fixed max-height would widen the band on
    // large windows and crop the backdrop more). Only clamp the extremes.
    final width = MediaQuery.sizeOf(context).width;
    final height = (width / 2.6).clamp(360.0, 760.0);
    final current = items[_page.clamp(0, items.length - 1)];
    // Backdrop lags the scroll for a parallax feel; capped to the Ken Burns
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Stack(
        fit: StackFit.expand,
        children: [
          // Swipeable backdrops with a slow Ken Burns zoom + scroll parallax.
          // Only this Transform rebuilds per scroll frame (via _scroll), the
          // PageView is passed as a const-ish child and isn't rebuilt.
          ValueListenableBuilder<double>(
            valueListenable: _scroll,
            child: PageView.builder(
              controller: _controller,
              // Paging is driven by the top-level drag layer (see below), so the
              // PageView itself doesn't scroll on input.
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) => _KenBurns(
                child: MediaImage(
                  item: items[i],
                  landscape: true,
                  maxWidth: 1920,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            builder: (context, scroll, child) {
              final dy = (scroll * 0.35).clamp(0.0, height * 0.045);
              return Transform.translate(offset: Offset(0, dy), child: child);
            },
          ),
          // Bottom scrim (fades art into the page).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    theme.colorScheme.surface.withValues(alpha: 0.35),
                    theme.colorScheme.surface.withValues(alpha: 0.97),
                  ],
                  stops: const [0.35, 0.72, 1],
                ),
              ),
            ),
          ),
          // Gentle left scrim for text legibility.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black54, Colors.transparent],
                  stops: [0.0, 0.45],
                ),
              ),
            ),
          ),
          // Content overlay — in the OUTER stack (bounded), so bottom-left is
          // reliable. Crossfades as the page changes. Width is capped at 620 on
          // wide windows but shrinks to fit the screen on a phone (left inset +
          // a right margin), so the logo and overview never clip off the edge.
          Positioned(
            left: 40,
            bottom: 34,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: SizedBox(
                key: ValueKey(current.id),
                width: (width - 64).clamp(0.0, 620.0),
                child: _HeroContent(item: current),
              ),
            ),
          ),
          if (items.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++)
                    // Tappable so you can jump straight to a slide.
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _goToPage(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          // A taller invisible hit area around the dot.
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: i == _page ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Drag-to-swipe surface, ABOVE the scrims so the pointer actually
          // reaches it (a bottom-layer detector was being covered). Translucent
          // so it claims horizontal drags to page the hero while taps still fall
          // through to the buttons and dots below. Works with mouse, finger, or
          // trackpad; vertical drags pass to Home's scroll untouched.
          if (items.length > 1)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: _onHeroDragUpdate,
                onHorizontalDragEnd: _onHeroDragEnd,
              ),
            ),
        ],
      ),
      ),
    );
  }
}

/// A series can't be played directly — start its next-up episode (or open the
/// show if nothing's queued). Folders open their page; movies/episodes play.
Future<void> heroPlay(
    BuildContext context, WidgetRef ref, BaseItemDto item) async {
  if (item.isSeries) {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session != null) {
      try {
        final next = await ref.read(jellyfinClientProvider).getNextUp(
              baseUrl: session.baseUrl,
              userId: session.userId,
              token: session.accessToken,
              seriesId: item.id,
            );
        if (next != null && context.mounted) {
          context.push('/player', extra: next);
          return;
        }
      } catch (_) {}
    }
    if (context.mounted) context.push('/item', extra: item);
  } else if (item.isFolder) {
    context.push('/item', extra: item);
  } else {
    context.push('/player', extra: item);
  }
}

class _HeroContent extends ConsumerWidget {
  final BaseItemDto item;
  const _HeroContent({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleOrLogo(item: item),
        const SizedBox(height: 10),
        _BannerMeta(item: item),
        if (item.overview != null && item.overview!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            item.overview!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            HeaderActionButton(
              icon: Icons.play_arrow_rounded,
              tooltip: l.commonPlay,
              onTap: () => heroPlay(context, ref, item),
              primary: true,
            ),
            const SizedBox(width: 10),
            HeaderActionButton(
              icon: Icons.info_outline_rounded,
              tooltip: l.browseDetails,
              onTap: () => context.push('/item', extra: item),
            ),
            const SizedBox(width: 10),
            _HeroFavButton(item: item),
          ],
        ),
      ],
    );
  }
}

/// A circular "add to favorites" toggle for the hero (the streaming ＋ button).
class _HeroFavButton extends ConsumerStatefulWidget {
  final BaseItemDto item;
  const _HeroFavButton({required this.item});

  @override
  ConsumerState<_HeroFavButton> createState() => _HeroFavButtonState();
}

class _HeroFavButtonState extends ConsumerState<_HeroFavButton> {
  late bool _fav = widget.item.userData.isFavorite;
  late String _forId = widget.item.id;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (widget.item.id != _forId) {
      _forId = widget.item.id;
      _fav = widget.item.userData.isFavorite;
    }
    return HeaderActionButton(
      icon: _fav ? Icons.check_rounded : Icons.add_rounded,
      tooltip: _fav ? l.browseInMyList : l.browseAddToMyList,
      onTap: () async {
        final session = ref.read(sessionControllerProvider).asData?.value;
        if (session == null) return;
        final next = !_fav;
        setState(() => _fav = next);
        try {
          await ref.read(jellyfinClientProvider).setFavorite(
                baseUrl: session.baseUrl,
                userId: session.userId,
                token: session.accessToken,
                itemId: widget.item.id,
                favorite: next,
              );
        } catch (_) {
          if (mounted) setState(() => _fav = !next);
        }
      },
    );
  }
}

/// Shows the title's logo art (a transparent PNG) when the server has one,
/// falling back to a bold text title. Both apps we're matching prefer logos.
class _TitleOrLogo extends ConsumerWidget {
  final BaseItemDto item;
  const _TitleOrLogo({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = Text(
      item.isEpisode ? (item.seriesName ?? item.name) : item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: Colors.white,
        shadows: const [Shadow(blurRadius: 14, color: Colors.black)],
      ),
    );

    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (!item.hasLogo || session == null) return text;

    final url = ref.watch(jellyfinClientProvider).imageUrl(
          baseUrl: session.baseUrl,
          itemId: item.logoItemId!,
          type: 'Logo',
          tag: item.logoTag,
          maxHeight: 160,
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 92, maxWidth: 460),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.network(
          url,
          headers: ref.watch(imageHeadersProvider),
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (_, _, _) => text,
        ),
      ),
    );
  }
}

/// A slow, gentle Ken Burns zoom for hero backdrops.
class _KenBurns extends StatefulWidget {
  final Widget child;
  const _KenBurns({required this.child});

  @override
  State<_KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<_KenBurns>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: hold a static, gently-overscaled frame (no zoom drift).
    if (reduceMotion(context)) {
      if (_c.isAnimating) _c.stop();
      return Transform.scale(
        scale: 1.16,
        filterQuality: FilterQuality.medium,
        child: RepaintBoundary(child: widget.child),
      );
    }
    if (!_c.isAnimating) _c.repeat(reverse: true);
    return AnimatedBuilder(
      animation: _c,
      // Rasterize the backdrop onto its own layer once; the scale below then
      // transforms that cached layer on the GPU each frame instead of
      // re-sampling the full bitmap through Skia, which is what made the zoom
      // shimmer/judder. The RepaintBoundary must sit INSIDE the animated
      // transform so it caches the static image, not the scaled result.
      child: RepaintBoundary(child: widget.child),
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c.value);
        // Base overscale gives parallax headroom so edges never reveal.
        return Transform.scale(
          scale: 1.1 + 0.12 * t,
          filterQuality: FilterQuality.medium,
          child: child,
        );
      },
    );
  }
}

/// A large, single-item "detailed" banner (Fladder-style): full-bleed backdrop
/// with logo/title, metadata, overview, genres, and actions. Shows one featured
/// item instead of a rotating carousel.
class DetailedHeroBanner extends StatelessWidget {
  final BaseItemDto item;
  const DetailedHeroBanner({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final height = (width / 2.4).clamp(380.0, 640.0);

    return SizedBox(
      height: height,
      child: ClipRect(
        child: Stack(
        fit: StackFit.expand,
        children: [
          _KenBurns(
            child: MediaImage(
              item: item,
              landscape: true,
              maxWidth: 1920,
              filterQuality: FilterQuality.medium,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    theme.colorScheme.surface.withValues(alpha: 0.4),
                    theme.colorScheme.surface.withValues(alpha: 0.98),
                  ],
                  stops: const [0.3, 0.7, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black54, Colors.transparent],
                  stops: [0.0, 0.5],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 24, 40, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Floating poster — the spotlight look.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.55),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 176,
                            height: 264,
                            child: MediaImage(item: item),
                          ),
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TitleOrLogo(item: item),
                              const SizedBox(height: 12),
                              _BannerMeta(item: item),
                              if (item.overview != null &&
                                  item.overview!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  item.overview!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                    height: 1.4,
                                    shadows: const [
                                      Shadow(blurRadius: 8, color: Colors.black)
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Consumer(
                                builder: (context, ref, _) => Row(
                                  children: [
                                    HeaderActionButton(
                                      icon: Icons.play_arrow_rounded,
                                      tooltip: AppLocalizations.of(context)
                                          .commonPlay,
                                      onTap: () =>
                                          heroPlay(context, ref, item),
                                      primary: true,
                                    ),
                                    const SizedBox(width: 12),
                                    HeaderActionButton(
                                      icon: Icons.info_outline_rounded,
                                      tooltip: AppLocalizations.of(context)
                                          .browseDetails,
                                      onTap: () =>
                                          context.push('/item', extra: item),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// A compact metadata line for the detailed banner (year · rating · runtime).
class _BannerMeta extends StatelessWidget {
  final BaseItemDto item;
  const _BannerMeta({required this.item});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
      if (item.officialRating != null) item.officialRating!,
      if (item.genres.isNotEmpty) item.genres.take(3).join(' · '),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('   ·   '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w600,
        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
      ),
    );
  }
}

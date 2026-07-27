import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../state/palette.dart';
import '../state/preferences.dart';
import '../widgets/featured_hero.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_section.dart';
import '../widgets/motion.dart';
import '../widgets/error_view.dart';
import '../widgets/shimmer.dart';

/// The library home: Continue Watching, Recently Added, and the user's
/// libraries. Tapping an item is a stub until detail + playback land next.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const double _posterRowHeight = 324;
  static const double _landscapeRowHeight = 210;
  static const double _resumeRowHeight = 238; // larger Continue Watching / Next Up

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final resume = ref.watch(resumeItemsProvider);
    final latest = ref.watch(latestItemsProvider);
    final hero = ref.watch(heroItemsProvider);
    final views = ref.watch(userViewsProvider);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();

    Future<void> refresh() async {
      ref.invalidate(resumeItemsProvider);
      ref.invalidate(nextUpItemsProvider);
      ref.invalidate(latestItemsProvider);
      ref.invalidate(heroItemsProvider);
      ref.invalidate(userViewsProvider);
      await Future.wait([
        ref.read(resumeItemsProvider.future),
        ref.read(latestItemsProvider.future),
        ref.read(userViewsProvider.future),
      ]);
    }

    final featured = hero.asData?.value;
    final heroItem = (featured != null && featured.isNotEmpty)
        ? featured.first
        : null;
    final accent = heroItem == null
        ? null
        : ref.watch(itemAccentProvider(heroItem)).asData?.value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Ambient, art-driven wash behind the whole page.
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                        (accent ?? scheme.primary).withValues(alpha: 0.28),
                        scheme.surface),
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
              slivers: [
            if (prefs.homeBanner != 'hide' &&
                hero.isLoading &&
                !hero.hasValue)
              const SliverToBoxAdapter(child: HomeHeroSkeleton())
            else if (prefs.homeBanner == 'carousel')
              SliverToBoxAdapter(
                child: FeaturedHero(items: hero.asData?.value ?? const []),
              )
            else if (prefs.homeBanner == 'detailed' && heroItem != null)
              SliverToBoxAdapter(
                child: DetailedHeroBanner(item: heroItem),
              ),

            // Rows in the user's chosen order (each gated by its toggle);
            // append any known rows missing from older saved orders.
            for (final rowId in <String>{
              ...prefs.homeRowOrder,
              'continueWatching',
              'nextUp',
              'recentlyAdded',
              'myMedia',
            })
              ?switch (rowId) {
                'continueWatching' => prefs.showContinueWatching
                    ? _sectionSliver(
                        context,
                        title: l.browseContinueWatching,
                        height: _resumeRowHeight,
                        async: resume,
                        onRetry: () => ref.invalidate(resumeItemsProvider),
                        cardBuilder: (item) => ContinueCard(
                          item: item,
                          onTap: () => context.push('/item', extra: item),
                        ),
                      )
                    : null,
                'nextUp' => prefs.showNextUp
                    ? _sectionSliver(
                        context,
                        title: l.browseNextUp,
                        height: _resumeRowHeight,
                        async: ref.watch(nextUpItemsProvider),
                        onRetry: () => ref.invalidate(nextUpItemsProvider),
                        cardBuilder: (item) => ContinueCard(
                          item: item,
                          onTap: () => context.push('/item', extra: item),
                        ),
                      )
                    : null,
                'recentlyAdded' => prefs.showRecentlyAdded
                    ? _sectionSliver(
                        context,
                        title: l.browseRecentlyAdded,
                        height: _posterRowHeight,
                        async: latest,
                        onRetry: () => ref.invalidate(latestItemsProvider),
                        cardBuilder: (item) => PosterCard(
                          item: item,
                          heroTag: 'home-recent-${item.id}',
                          onTap: () => context.push('/item', extra: item),
                        ),
                      )
                    : null,
                'myMedia' => prefs.showMyMedia
                    ? _sectionSliver(
                        context,
                        title: l.browseMyMedia,
                        height: _landscapeRowHeight,
                        // Live TV has its own nav destination and opens nothing
                        // as a /library tile, so exclude it here like the
                        // Libraries hub and the sidebar do.
                        async: views.whenData((list) => list
                            .where((v) => v.collectionType != 'livetv')
                            .toList()),
                        hideWhenEmpty: false,
                        cardBuilder: (item) => LibraryCard(
                          item: item,
                          onTap: () => context.push('/library', extra: item),
                        ),
                      )
                    : null,
                _ => null,
              },

            // Per-library "Latest in X" rows, mirroring Jellyfin's home.
            if (prefs.showLibraryLatest)
              for (final view in (views.asData?.value ?? const <BaseItemDto>[])
                  .where((v) =>
                      v.collectionType == 'movies' ||
                      v.collectionType == 'tvshows'))
                _sectionSliver(
                  context,
                  title: l.browseLatestIn(view.name),
                  height: _posterRowHeight,
                  async: ref.watch(latestInLibraryProvider(view.id)),
                  onRetry: () =>
                      ref.invalidate(latestInLibraryProvider(view.id)),
                  onSeeAll: () => context.push('/library', extra: view),
                  cardBuilder: (item) => PosterCard(
                    item: item,
                    heroTag: 'home-latest-${view.id}-${item.id}',
                    onTap: () => context.push('/item', extra: item),
                  ),
                ),

            // Editorial genre rows for browsing variety.
            if (prefs.showGenreRows)
              for (final genre
                  in (ref.watch(genresProvider).asData?.value ??
                          const <BaseItemDto>[])
                      .take(6))
                _sectionSliver(
                  context,
                  title: genre.name,
                  height: _posterRowHeight,
                  async: ref.watch(genreItemsProvider(
                      (genre: genre.name, sortBy: 'Random', sortOrder: 'Ascending'))),
                  onSeeAll: () => context.push('/genre', extra: genre.name),
                  cardBuilder: (item) => PosterCard(
                    item: item,
                    heroTag: 'home-genre-${genre.name}-${item.id}',
                    onTap: () => context.push('/item', extra: item),
                  ),
                ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          // Home has no app bar (the hero fills the top), so on a phone a small
          // floating button opens the navigation drawer, with a scrim behind it
          // for legibility over bright hero art.
          if (MediaQuery.of(context).size.shortestSide < 600)
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 8,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                    color: Colors.black26, shape: BoxShape.circle),
                child: DrawerMenuButton(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionSliver(
    BuildContext context, {
    required String title,
    required double height,
    required AsyncValue<List<BaseItemDto>> async,
    required Widget Function(BaseItemDto) cardBuilder,
    bool hideWhenEmpty = true,
    VoidCallback? onSeeAll,
    VoidCallback? onRetry,
  }) {
    final l = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: async.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, title),
            SectionSkeleton(height: height),
          ],
        ),
        error: (e, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, title),
            SectionError(
                message: l.browseCouldNotLoad(title), onRetry: onRetry),
          ],
        ),
        data: (items) {
          if (items.isEmpty && hideWhenEmpty) return const SizedBox.shrink();
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(context, title),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(l.browseNothingHereYet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ],
            );
          }
          return MediaSection(
            title: title,
            height: height,
            onSeeAll: onSeeAll,
            children: [
              for (var i = 0; i < items.length; i++)
                EntranceFade(
                    index: i,
                    onceKey: items[i].id,
                    child: cardBuilder(items[i])),
            ],
          );
        },
      ),
    );
  }

  Widget _title(BuildContext context, String title) =>
      SectionHeader(title: title);
}

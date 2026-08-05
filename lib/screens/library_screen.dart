import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/providers.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_image.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';
import '../widgets/tv_focus.dart';

/// Full contents of one library, as a paged poster grid with infinite scroll.
class LibraryScreen extends ConsumerStatefulWidget {
  final BaseItemDto library;
  const LibraryScreen({super.key, required this.library});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _pageSize = 100;
  final _scroll = ScrollController();
  final List<BaseItemDto> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  String _sortBy = 'SortName';
  String _sortOrder = 'Ascending';
  bool _unwatchedOnly = false;
  bool _favoritesOnly = false;
  String? _genre;
  bool _filtersOpen = false;
  List<BaseItemDto> _genres = const [];
  bool _genresLoaded = false;

  int get _activeFilters =>
      (_unwatchedOnly ? 1 : 0) +
      (_favoritesOnly ? 1 : 0) +
      (_genre != null ? 1 : 0);

  void _reload() {
    setState(() {
      _items.clear();
      _total = 0;
      _loadedOnce = false;
      _error = null;
    });
    _loadMore();
  }

  String? get _includeTypes {
    switch (widget.library.collectionType) {
      case 'movies':
        return 'Movie';
      case 'tvshows':
        return 'Series';
      case 'music':
        return 'MusicAlbum';
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    if (_loadedOnce && _items.length >= _total) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(jellyfinClientProvider).getItems(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            parentId: widget.library.id,
            includeItemTypes: _includeTypes,
            recursive: _includeTypes != null,
            sortBy: _sortBy,
            sortOrder: _sortOrder,
            filters: _unwatchedOnly ? 'IsUnplayed' : null,
            isFavorite: _favoritesOnly ? true : null,
            genres: _genre,
            startIndex: _items.length,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _total = res.totalRecordCount;
        _loadedOnce = true;
      });
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleFilters() {
    setState(() => _filtersOpen = !_filtersOpen);
    if (_filtersOpen && !_genresLoaded) _loadGenres();
  }

  Future<void> _loadGenres() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    try {
      final g = await ref.read(jellyfinClientProvider).getGenres(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            parentId: widget.library.id,
          );
      if (mounted) setState(() => _genres = g);
    } catch (_) {
      // Leave genres empty; toggles still work.
    } finally {
      if (mounted) setState(() => _genresLoaded = true);
    }
  }

  /// Inline, collapsible filter panel (rendered in the body — no modal, which
  /// wouldn't display from this screen).
  Widget _filterPanel() {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(l.browseFilter,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (_activeFilters > 0)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _unwatchedOnly = false;
                        _favoritesOnly = false;
                        _genre = null;
                      });
                      _reload();
                    },
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: Text(l.commonClear),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilterChip(
                    label: Text(l.browseUnwatched),
                    selected: _unwatchedOnly,
                    onSelected: (v) {
                      setState(() => _unwatchedOnly = v);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilterChip(
                    label: Text(l.browseFavorites),
                    selected: _favoritesOnly,
                    onSelected: (v) {
                      setState(() => _favoritesOnly = v);
                      _reload();
                    },
                  ),
                ),
              ],
            ),
            if (!_genresLoaded)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_genres.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(l.browseGenre,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.browseAll),
                    selected: _genre == null,
                    onSelected: (_) {
                      setState(() => _genre = null);
                      _reload();
                    },
                  ),
                  for (final g in _genres)
                    ChoiceChip(
                      label: Text(g.name),
                      selected: _genre == g.name,
                      onSelected: (_) {
                        setState(() => _genre = g.name);
                        _reload();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sortOptions = _browseSortOptions(l);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.library.name),
        actions: [
          IconButton(
            tooltip: l.browseFilters,
            isSelected: _activeFilters > 0,
            icon: Badge(
              isLabelVisible: _activeFilters > 0,
              label: Text('$_activeFilters'),
              child: Icon(_activeFilters > 0
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined),
            ),
            onPressed: _toggleFilters,
          ),
          IconButton(
            tooltip:
                _sortOrder == 'Ascending' ? l.browseAscending : l.browseDescending,
            icon: Icon(_sortOrder == 'Ascending'
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded),
            onPressed: () {
              setState(() => _sortOrder =
                  _sortOrder == 'Ascending' ? 'Descending' : 'Ascending');
              _reload();
            },
          ),
          Builder(builder: (context) {
            final grid = ref
                    .watch(preferencesProvider)
                    .asData
                    ?.value
                    .libraryViewMode !=
                'list';
            return IconButton(
              tooltip: grid ? l.browseListView : l.browseGridView,
              icon: Icon(grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded),
              onPressed: () => ref.read(preferencesProvider.notifier).edit(
                  (x) => x.copyWith(
                      libraryViewMode: grid ? 'list' : 'grid')),
            );
          }),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: l.browseSortBy,
            initialValue: _sortBy,
            onSelected: (v) {
              setState(() {
                _sortBy = v;
                _sortOrder = v == 'SortName' ? 'Ascending' : 'Descending';
              });
              _reload();
            },
            itemBuilder: (_) => [
              for (final e in sortOptions.entries)
                CheckedPopupMenuItem(
                  value: e.key,
                  checked: _sortBy == e.key,
                  child: Text(e.value),
                ),
            ],
          ),
        ],
        bottom: _total > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(l.browseItemsCount(_total),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _filtersOpen
                ? _filterPanel()
                : const SizedBox(width: double.infinity),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (!_loadedOnce && _loading) {
      return const PosterGridSkeleton();
    }
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return EmptyState(
          icon: Icons.inbox_rounded,
          title: AppLocalizations.of(context).browseLibraryEmpty);
    }
    final listView =
        ref.watch(preferencesProvider).asData?.value.libraryViewMode == 'list';
    if (listView) {
      return ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => EntranceFade(
          index: i,
          onceKey: _items[i].id,
          child: _LibraryListRow(
            item: _items[i],
            autofocus: isTvDevice && i == 0,
            onTap: () => context.push('/item', extra: _items[i]),
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 184,
        mainAxisSpacing: 18,
        crossAxisSpacing: 14,
        childAspectRatio: 0.54,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) => EntranceFade(
        index: i,
        onceKey: _items[i].id,
        child: PosterTile(
          item: _items[i],
          // On TV the first tile grabs focus so the remote lands on content, not
          // the app bar back button.
          autofocus: isTvDevice && i == 0,
          onTap: () => context.push('/item', extra: _items[i]),
        ),
      ),
    );
  }
}

/// A compact library row for list view: small poster, title, meta, and a
/// watched tick.
class _LibraryListRow extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback onTap;
  final bool autofocus;
  const _LibraryListRow(
      {required this.item, required this.onTap, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.officialRating != null) item.officialRating!,
    ].join('  ·  ');
    final watched = item.userData.played;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(10),
      child: HoverHighlight(
      child: ListTile(
        autofocus: autofocus,
        // HoverHighlight provides the hover tint; suppress ListTile's own so
        // they don't stack.
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child:
              SizedBox(width: 46, height: 69, child: MediaImage(item: item)),
        ),
        title: Text(item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: meta.isEmpty
            ? null
            : Text(meta,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        trailing: watched
            ? Icon(Icons.check_circle,
                size: 18, color: theme.colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    ),
    );
  }
}

/// Library sort options as a map of Jellyfin sort key -> localized label.
/// A function (not a const map) so the labels can be localized.
Map<String, String> _browseSortOptions(AppLocalizations l) => {
      'SortName': l.browseSortName,
      'DateCreated': l.browseSortDateAdded,
      'PremiereDate': l.browseSortReleaseDate,
      'CommunityRating': l.browseSortRating,
      'Random': l.browseSortRandom,
    };

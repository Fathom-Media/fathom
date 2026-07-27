import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/seerr_providers.dart';
import '../state/session_controller.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/score_pills.dart';
import '../widgets/glass.dart';
import '../widgets/cast_button.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/motion.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_image.dart';
import '../widgets/media_section.dart';
import '../widgets/detail_header.dart';
import '../widgets/meta_pill.dart';
import '../widgets/shimmer.dart';
import 'album_screen.dart';
import 'collection_view.dart';

/// Item detail: backdrop, metadata, overview, a Play/Resume action, and — for
/// series — an episode list. Tapping Play opens the media_kit player.
class DetailScreen extends ConsumerWidget {
  final BaseItemDto item;
  const DetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(itemDetailProvider(item.id));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (e, _) => _ErrorState(message: '$e'),
        data: (full) => BackdropBackground(
          item: full,
          child: full.type == 'BoxSet'
              ? CollectionView(collection: full)
              : full.isAlbum
                  ? AlbumView(album: full)
                  : _DetailBody(item: full),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final BaseItemDto item;
  const _DetailBody({required this.item});

  Future<void> _play(
      BuildContext context, WidgetRef ref, BaseItemDto playItem,
      {bool resume = true}) async {
    await context.push('/player',
        extra: resume ? playItem : (item: playItem, resume: false));
    // Back from the player: refresh resume position + Home rows.
    ref.invalidate(itemDetailProvider(item.id));
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(latestItemsProvider);
    ref.invalidate(nextUpItemsProvider);
    if (item.isSeries) {
      ref.invalidate(episodesProvider(item.id));
      ref.invalidate(nextUpProvider(item.id));
    }
  }

  Future<void> _togglePlayed(WidgetRef ref) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    await ref.read(jellyfinClientProvider).setPlayed(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: item.id,
          played: !item.userData.played,
        );
    ref.invalidate(itemDetailProvider(item.id));
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(latestItemsProvider);
  }

  Future<void> _toggleFavorite(WidgetRef ref) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    await ref.read(jellyfinClientProvider).setFavorite(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: item.id,
          favorite: !item.userData.isFavorite,
        );
    ref.invalidate(itemDetailProvider(item.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Scale the backdrop band with width so it keeps a consistent aspect and
    // isn't cropped into a thin sliver on wide windows. A taller band (closer
    // to the art's 16:9 shape) means less of the backdrop is cropped away.
    final headerHeight =
        (MediaQuery.sizeOf(context).width / 2.35).clamp(320.0, 680.0);

    // Ratings + meta for the header marquee, enriched with Seerr's RT audience
    // and IMDb scores when we have a TMDB id, so the header matches Seerr.
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final tmdb = int.tryParse(item.tmdbId ?? '');
    final seerrType = item.seerrMediaType;
    final ext = (tmdb != null && seerrType != null)
        ? ref
            .watch(jellyfinItemRatingsProvider(
                (mediaType: seerrType, tmdbId: tmdb)))
            .asData
            ?.value
        : null;
    final mdb = (tmdb != null && seerrType != null)
        ? ref
            .watch(mdbListRatingsProvider(
                (mediaType: seerrType, tmdbId: tmdb)))
            .asData
            ?.value
        : null;
    final ratingPills = scorePills(
      // Native first, then MDBList as gap-fill (never overwrites a real value).
      rtCritic: ext?.rtCritic ?? item.criticRating?.round() ?? mdb?.rtCritic,
      rtAudience: ext?.rtAudience ?? mdb?.rtAudience,
      imdb: ext?.imdb ?? (mdb?.imdb != null ? mdb!.imdb! / 10 : null),
      community: item.communityRating ??
          (mdb?.tmdb != null ? mdb!.tmdb! / 10 : null),
      letterboxd: mdb?.letterboxd,
      metacritic: mdb?.metacritic,
      metacriticUser: mdb?.metacriticUser,
      trakt: mdb?.trakt,
      rogerEbert: mdb?.rogerEbert,
      myAnimeList: mdb?.myAnimeList,
      prefs: prefs,
    );
    final metaLine = item.isEpisode
        ? _episodeLine(item)
        : [
            item.type == 'Series' ? l.detailSeries : l.detailMovie,
            if (item.productionYear != null) '${item.productionYear}',
            if (item.runtimeMinutes != null) fmtRuntime(item.runtimeMinutes!),
          ].join('  ·  ');

    // Actions as circular icons in the header on wide windows, as labelled
    // buttons in the body on narrow ones.
    final wideHeader = MediaQuery.sizeOf(context).width >= 620;
    // For a series, Play targets Next Up. When there isn't one — a recorded
    // series (which is how a recording opened from a library shows up), or
    // everything already watched — fall back to the first episode so Play is
    // never a silent dead button.
    final nextUp = item.isSeries
        ? ref.watch(nextUpProvider(item.id)).asData?.value
        : null;
    final seriesEpisodes = item.isSeries
        ? (ref.watch(episodesProvider(item.id)).asData?.value ??
            const <BaseItemDto>[])
        : const <BaseItemDto>[];
    final playTarget = item.isSeries
        ? (nextUp ?? (seriesEpisodes.isEmpty ? null : seriesEpisodes.first))
        : item;
    final headerActionIcons = <Widget>[
      HeaderActionButton(
        icon: Icons.play_arrow_rounded,
        tooltip: playTarget == null
            ? l.commonPlay
            : (playTarget.canResume ? l.detailResume : l.commonPlay),
        primary: true,
        onTap:
            playTarget == null ? null : () => _play(context, ref, playTarget),
      ),
      if (!item.isSeries && item.canResume)
        HeaderActionButton(
          icon: Icons.replay_rounded,
          tooltip: l.detailPlayFromStart,
          onTap: () => _play(context, ref, item, resume: false),
        ),
      if (item.trailerUrl != null) _TrailerButton(item: item, header: true),
      if (!item.isAlbum) ...[
        _RemoteButton(item: item, header: true),
        _DownloadButton(item: item, header: true),
      ],
    ];
    final headerActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < headerActionIcons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          headerActionIcons[i],
        ],
      ],
    );

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: headerHeight,
          pinned: true,
          stretch: true,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: item.userData.played
                  ? l.detailMarkUnwatched
                  : l.detailMarkWatched,
              icon: _PopIcon(
                selected: item.userData.played,
                icon: Icons.check_circle_rounded,
                iconOff: Icons.check_circle_outline_rounded,
              ),
              onPressed: () => _togglePlayed(ref),
            ),
            IconButton(
              tooltip: item.userData.isFavorite
                  ? l.detailRemoveFavorite
                  : l.detailAddFavorite,
              icon: _PopIcon(
                selected: item.userData.isFavorite,
                icon: Icons.favorite_rounded,
                iconOff: Icons.favorite_border_rounded,
                selectedColor: Colors.redAccent,
              ),
              onPressed: () => _toggleFavorite(ref),
            ),
            _ItemMenu(item: item),
          ],
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [
              StretchMode.zoomBackground,
              StretchMode.blurBackground,
            ],
            background: Stack(
              fit: StackFit.expand,
              children: [
                MediaImage(
                  item: item,
                  landscape: true,
                  maxWidth: 1920,
                  alignment: const Alignment(0, -0.35),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                        scheme.surface.withValues(alpha: 0.6),
                      ],
                      stops: const [0, 0.45, 0.82, 1],
                    ),
                  ),
                ),
                DetailHeaderOverlay(
                  poster: Hero(
                    tag: 'art-${item.id}',
                    child: MediaImage(item: item),
                  ),
                  title: _DetailTitle(item: item, onDark: true),
                  cert: item.officialRating != null
                      ? CertBadge(text: item.officialRating!)
                      : null,
                  metaLine: metaLine,
                  ratings: ratingPills,
                  actions: wideHeader ? headerActions : null,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!wideHeader) ...[
                  _ActionBar(
                    item: item,
                    onPlay: (playItem, {bool resume = true}) =>
                        _play(context, ref, playItem, resume: resume),
                  ),
                  const SizedBox(height: 4),
                ],
                if (item.overview != null && item.overview!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(item.overview!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ],
                if (item.genres.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.genres
                        .map((g) => ActionChip(
                              label: Text(g),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  context.push('/genre', extra: g),
                            ))
                        .toList(),
                  ),
                ],
                if (item.people.isNotEmpty) _CastSection(people: item.people),
              ],
            ),
          ),
        ),
        if (item.isSeries) _NextUpSection(seriesId: item.id),
        if (item.isSeries) _EpisodeList(seriesId: item.id),
        if (!item.isEpisode) _MoreLikeThis(itemId: item.id),
      ],
    );
  }

  static String _episodeLine(BaseItemDto item) {
    final s = item.parentIndexNumber, e = item.indexNumber;
    final se = (s != null && e != null) ? 'S$s:E$e · ' : '';
    return '$se${item.name}';
  }
}

class _EpisodeList extends ConsumerStatefulWidget {
  final String seriesId;
  const _EpisodeList({required this.seriesId});

  @override
  ConsumerState<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends ConsumerState<_EpisodeList> {
  int? _season;

  String _seasonLabel(int n) {
    final l = AppLocalizations.of(context);
    return n == 0 ? l.detailSpecials : l.detailSeasonNumber(n);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final episodes = ref.watch(episodesProvider(widget.seriesId));
    return episodes.when(
      loading: () =>
          const SliverToBoxAdapter(child: EpisodeListSkeleton()),
      error: (e, _) => SliverToBoxAdapter(child: _ErrorState(message: '$e')),
      data: (items) {
        if (items.isEmpty) return const SliverToBoxAdapter();
        final seasons = items
            .map((e) => e.parentIndexNumber ?? 0)
            .toSet()
            .toList()
          ..sort();
        final current = seasons.contains(_season) ? _season! : seasons.first;
        final shown = seasons.length > 1
            ? items
                .where((e) => (e.parentIndexNumber ?? 0) == current)
                .toList()
            : items;
        return SliverList.builder(
          itemCount: shown.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Text(l.detailEpisodes,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (seasons.length > 1)
                      DropdownButton<int>(
                        value: current,
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(12),
                        items: [
                          for (final s in seasons)
                            DropdownMenuItem(
                                value: s, child: Text(_seasonLabel(s))),
                        ],
                        onChanged: (v) => setState(() => _season = v),
                      ),
                  ],
                ),
              );
            }
            final ep = shown[i - 1];
            return HoverHighlight(
              child: _EpisodeTile(
                episode: ep,
                onTap: () async {
                  await context.push('/player', extra: ep);
                  ref.invalidate(episodesProvider(widget.seriesId));
                  ref.invalidate(resumeItemsProvider);
                  ref.invalidate(nextUpProvider(widget.seriesId));
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final BaseItemDto episode;
  final VoidCallback onTap;
  const _EpisodeTile({required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final played = episode.userData.played;
    final label = episode.indexNumber != null
        ? '${episode.indexNumber}. ${episode.name}'
        : episode.name;
    return ListTile(
      hoverColor: Colors.transparent, // HoverHighlight handles the hover tint
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: SizedBox(
        width: 96,
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaImage(item: episode, landscape: true),
            ),
            if (played)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  decoration: BoxDecoration(
                      color: scheme.primary, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.check_rounded,
                      size: 12, color: scheme.onPrimary),
                ),
              ),
            if (!played && episode.progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8)),
                  child: LinearProgressIndicator(
                      value: episode.progress, minHeight: 3),
                ),
              ),
          ],
        ),
      ),
      title: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: played ? TextStyle(color: scheme.onSurfaceVariant) : null),
      subtitle: episode.runtimeMinutes != null
          ? Text(l.detailRuntimeMinutes(episode.runtimeMinutes!),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant))
          : null,
      trailing: Icon(episode.canResume
          ? Icons.play_circle_outline_rounded
          : Icons.play_arrow_rounded),
      onTap: onTap,
    );
  }
}

/// Download / offline-copy button reflecting the item's download state.
class _DownloadButton extends ConsumerWidget {
  final BaseItemDto item;
  final bool header;
  const _DownloadButton({required this.item, this.header = false});

  Widget _btn({
    required IconData icon,
    required String tooltip,
    required String label,
    required VoidCallback? onTap,
    Widget? iconOverride,
  }) =>
      header
          ? HeaderActionButton(
              icon: icon,
              tooltip: tooltip,
              label: label,
              onTap: onTap,
              iconOverride: iconOverride)
          : HoverPillButton(
              icon: icon,
              label: label,
              onTap: onTap,
              iconWidget: iconOverride,
            );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entry = ref.watch(downloadsProvider).asData?.value[item.id];
    if (entry == null) {
      return _btn(
        icon: Icons.download_rounded,
        tooltip: l.detailDownload,
        label: l.detailDownload,
        onTap: () => ref.read(downloadsProvider.notifier).download(item),
      );
    }
    switch (entry.status) {
      case DownloadStatus.downloading:
        return _btn(
          icon: Icons.download_rounded,
          tooltip: l.detailDownloadingTooltip,
          label: l.detailDownloading,
          onTap: null,
          iconOverride: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                value: entry.progress > 0 ? entry.progress : null,
                strokeWidth: 2.5,
                color: header ? Colors.white : null),
          ),
        );
      case DownloadStatus.complete:
        return _btn(
          icon: Icons.download_done_rounded,
          tooltip: l.detailDownloadedTooltip,
          label: l.detailDownloaded,
          onTap: () => _confirmDelete(context, ref),
        );
      case DownloadStatus.failed:
        return _btn(
          icon: Icons.error_outline_rounded,
          tooltip: l.detailDownloadFailedTooltip,
          label: l.commonRetry,
          onTap: () => ref.read(downloadsProvider.notifier).download(item),
        );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.detailRemoveDownload),
        content: Text(l.detailRemoveOfflineCopy(item.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonRemove)),
        ],
      ),
    );
    if (ok == true) ref.read(downloadsProvider.notifier).delete(item.id);
  }
}

/// "Play on Another Device" — casts the item to another controllable player.
class _RemoteButton extends ConsumerWidget {
  final BaseItemDto item;
  final bool header;
  const _RemoteButton({required this.item, this.header = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (header) {
      return HeaderActionButton(
        icon: Icons.settings_remote_rounded,
        tooltip: l.detailPlayOnAnotherDevice,
        label: l.detailCastAction,
        onTap: () => _showDevices(context, ref),
      );
    }
    return HoverPillButton(
      icon: Icons.settings_remote_rounded,
      label: l.detailCastAction,
      onTap: () => _showDevices(context, ref),
    );
  }

  Future<void> _showDevices(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> devices;
    try {
      devices = await client.getControllableSessions(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!context.mounted) return;
    if (devices.isEmpty) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.detailNoControllableDevices)));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          // Cap the sheet and let the device list scroll rather than overflow.
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(l.detailPlayOnAnotherDeviceTitle,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in devices)
                      ListTile(
                        leading: const Icon(Icons.cast_rounded),
                        title: Text(
                            '${d['DeviceName'] ?? d['Client'] ?? l.detailDevice}'),
                        subtitle: Text('${d['Client'] ?? ''}'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await client.playOnSession(
                              baseUrl: session.baseUrl,
                              token: session.accessToken,
                              sessionId: '${d['Id']}',
                              itemId: item.id,
                            );
                            messenger.showSnackBar(SnackBar(
                                content: Text(l.detailPlayingOn(
                                    '${d['DeviceName'] ?? l.detailDevice}'))));
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overflow menu with management actions, shown only for actions the user's
/// policy permits (delete / metadata refresh).
class _ItemMenu extends ConsumerWidget {
  final BaseItemDto item;
  const _ItemMenu({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final user = ref.watch(currentUserProvider).asData?.value;
    final canDelete = (user?.enableContentDeletion ?? false) ||
        (user?.isAdministrator ?? false) ||
        session.canDelete;
    final canRefresh = (user?.isAdministrator ?? false) || session.isAdmin;
    // "Add to Playlist" is available to everyone; refresh/delete are gated.

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) => _onSelected(context, ref, session, v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'playlist',
          child: ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: Text(l.detailAddToPlaylist),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canRefresh)
          PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(l.detailRefreshMetadata),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text(l.commonDelete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, WidgetRef ref,
      dynamic session, String value) async {
    final l = AppLocalizations.of(context);
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (value == 'playlist') {
      await showAddToPlaylistSheet(context, ref,
          itemIds: [item.id], label: item.name);
    } else if (value == 'refresh') {
      try {
        await client.refreshItem(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            itemId: item.id);
        messenger.showSnackBar(
            SnackBar(content: Text(l.detailMetadataRefreshStarted)));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    } else if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.detailDeleteItem),
          content: Text(l.detailDeleteConfirm(item.name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonDelete),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await client.deleteItem(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            itemId: item.id);
        ref.invalidate(resumeItemsProvider);
        ref.invalidate(latestItemsProvider);
        ref.invalidate(favoriteItemsProvider);
        if (context.mounted) {
          context.pop();
          messenger.showSnackBar(
              SnackBar(content: Text(l.detailDeleted(item.name))));
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// An icon that pops (scale-fades) when its selected state flips.
class _PopIcon extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData iconOff;
  final Color? selectedColor;

  const _PopIcon({
    required this.selected,
    required this.icon,
    required this.iconOff,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: Icon(
        selected ? icon : iconOff,
        key: ValueKey(selected),
        color: selected ? selectedColor : null,
      ),
    );
  }
}

class _CastSection extends StatelessWidget {
  final List<Person> people;
  const _CastSection({required this.people});

  @override
  Widget build(BuildContext context) {
    // Billed cast first (Actors), then the rest of the crew.
    final cast = [...people]..sort((a, b) {
        int rank(Person p) => p.type == 'Actor' ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
    final shown = cast.take(30).toList();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(l.detailCastCrew,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 158,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _PersonCard(person: shown[i]),
          ),
        ),
      ],
    );
  }
}

class _PersonCard extends StatefulWidget {
  final Person person;
  const _PersonCard({required this.person});

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = widget.person;
    final role = person.role?.isNotEmpty == true
        ? person.role!
        : (person.type ?? '');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: person.id.isEmpty
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: person.id.isEmpty
            ? null
            : () => context.push('/person', extra: person),
        child: SizedBox(
          width: 100,
          child: Column(
            children: [
              AnimatedScale(
                scale: _hover ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: _PersonAvatar(
                  person: person,
                  size: 84,
                  ring: _hover ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(person.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (role.isNotEmpty)
                Text(role,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonAvatar extends ConsumerWidget {
  final Person person;
  final double size;
  final Color? ring;
  const _PersonAvatar({required this.person, this.size = 64, this.ring});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);

    Widget placeholder() => Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.person_rounded,
              color: scheme.onSurfaceVariant, size: size * 0.5),
        );

    Widget inner;
    if (session == null ||
        person.primaryImageTag == null ||
        person.id.isEmpty) {
      inner = placeholder();
    } else {
      final url = client.imageUrl(
        baseUrl: session.baseUrl,
        itemId: person.id,
        type: 'Primary',
        tag: person.primaryImageTag,
        maxHeight: 200,
      );
      inner = Image.network(
        url,
        fit: BoxFit.cover,
        headers: headers,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring != null ? Border.all(color: ring!, width: 2.5) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(width: size, height: size, child: inner),
      ),
    );
  }
}

class _NextUpSection extends ConsumerWidget {
  final String seriesId;
  const _NextUpSection({required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextUp = ref.watch(nextUpProvider(seriesId));
    return nextUp.when(
      loading: () => const SliverToBoxAdapter(),
      error: (_, _) => const SliverToBoxAdapter(),
      data: (ep) {
        if (ep == null) return const SliverToBoxAdapter();
        final l = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final label = (ep.parentIndexNumber != null && ep.indexNumber != null)
            ? 'S${ep.parentIndexNumber}:E${ep.indexNumber} · ${ep.name}'
            : ep.name;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.detailNextUp,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await context.push('/player', extra: ep);
                    ref.invalidate(nextUpProvider(seriesId));
                    ref.invalidate(episodesProvider(seriesId));
                    ref.invalidate(resumeItemsProvider);
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 150,
                          height: 84,
                          child: MediaImage(item: ep, landscape: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.play_arrow_rounded,
                                  size: 18, color: theme.colorScheme.primary),
                              Text(ep.canResume ? l.detailResume : l.commonPlay,
                                  style: TextStyle(
                                      color: theme.colorScheme.primary)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Premium metadata row: year, runtime, community rating, and an outlined
/// certification badge, as pills.
/// A soft rounded metadata pill.
/// The primary action row (play/resume + watched/favorite + remote/download),
/// wrapping onto multiple lines when the column is narrow.
class _ActionBar extends ConsumerWidget {
  final BaseItemDto item;
  final void Function(BaseItemDto playItem, {bool resume}) onPlay;
  const _ActionBar({required this.item, required this.onPlay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    // For a series, the primary Play targets the next-up episode.
    if (item.isSeries) {
      final next = ref.watch(nextUpProvider(item.id)).asData?.value;
      final code = (next?.parentIndexNumber != null &&
              next?.indexNumber != null)
          ? 'S${next!.parentIndexNumber}:E${next.indexNumber}'
          : null;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HoverPillButton(
            primary: true,
            icon: Icons.play_arrow_rounded,
            label: next == null
                ? l.commonPlay
                : (next.canResume
                    ? (code == null ? l.detailResume : l.detailResumeCode(code))
                    : (code == null ? l.commonPlay : l.detailPlayCode(code))),
            onTap: next == null ? null : () => onPlay(next),
          ),
          if (next != null) _ChromecastButton(target: next),
          if (item.trailerUrl != null) _TrailerButton(item: item),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        HoverPillButton(
          primary: true,
          icon: Icons.play_arrow_rounded,
          label: item.canResume
              ? l.detailResumeFrom(_fmtTicks(item.resumePositionTicks))
              : l.commonPlay,
          onTap: () => onPlay(item),
        ),
        if (item.canResume)
          HoverPillButton(
            icon: Icons.replay_rounded,
            label: l.detailPlayFromStart,
            onTap: () => onPlay(item, resume: false),
          ),
        if (item.trailerUrl != null) _TrailerButton(item: item),
        if (!item.isAlbum) ...[
          _ChromecastButton(target: item),
          _RemoteButton(item: item),
          _DownloadButton(item: item),
        ],
      ],
    );
  }
}

/// A Chromecast button on the detail page: casts [target] to a Cast device and
/// opens the player so its cast remote is shown. Hides itself where Cast isn't
/// available (desktop, or no Google Play Services), so it only appears when
/// there's actually something to cast to.
class _ChromecastButton extends ConsumerWidget {
  final BaseItemDto target;
  const _ChromecastButton({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CastButton(
      title: target.name,
      resolve: () async {
        final session = ref.read(sessionControllerProvider).asData?.value;
        if (session == null) return null;
        try {
          return await ref.read(jellyfinClientProvider).castStream(
                baseUrl: session.baseUrl,
                userId: session.userId,
                token: session.accessToken,
                itemId: target.id,
              );
        } catch (_) {
          return null;
        }
      },
      onStarted: () => context.push('/player', extra: target),
    );
  }
}

/// Compact trailer button that sits alongside Play / Cast / Download.
class _TrailerButton extends StatelessWidget {
  final BaseItemDto item;
  final bool header;
  const _TrailerButton({required this.item, this.header = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void open() => context.push('/trailer',
        extra: (url: item.trailerUrl!, title: item.name));
    if (header) {
      return HeaderActionButton(
          icon: Icons.movie_outlined,
          tooltip: l.detailWatchTrailer,
          label: l.detailTrailer,
          onTap: open);
    }
    return HoverPillButton(
      icon: Icons.movie_outlined,
      label: l.detailTrailer,
      onTap: open,
    );
  }
}

/// An outlined content-rating (certification) badge, e.g. "TV-14".
/// Loading placeholder for the detail screen (backdrop band + poster + lines),
/// so it doesn't flash a bare spinner then jump to the full layout.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ShimmerBox(
          height: (w / 2.35).clamp(320.0, 680.0),
          borderRadius: BorderRadius.zero,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 150, height: 225),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ShimmerBox(width: 240, height: 34),
                    const SizedBox(height: 14),
                    ShimmerBox(width: w * 0.4, height: 16),
                    const SizedBox(height: 18),
                    const ShimmerBox(width: 150, height: 48),
                    const SizedBox(height: 20),
                    ShimmerBox(width: w * 0.5, height: 14),
                    const SizedBox(height: 8),
                    ShimmerBox(width: w * 0.45, height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    );
  }
}

String _fmtTicks(int ticks) {
  final total = ticks ~/ 10000000; // ticks(100ns) -> seconds
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// The detail title: the show/movie's logo art when the server has one, else a
/// bold text title (matching the Home hero's treatment).
class _DetailTitle extends ConsumerWidget {
  final BaseItemDto item;

  /// Rendered over the backdrop: white text with a shadow, for legibility.
  final bool onDark;
  const _DetailTitle({required this.item, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = Text(
      item.isEpisode ? (item.seriesName ?? item.name) : item.name,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: onDark ? Colors.white : null,
        shadows: onDark
            ? const [Shadow(blurRadius: 8, color: Colors.black)]
            : null,
      ),
    );
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (item.isEpisode || !item.hasLogo || session == null) return text;

    final url = ref.watch(jellyfinClientProvider).imageUrl(
          baseUrl: session.baseUrl,
          itemId: item.logoItemId!,
          type: 'Logo',
          tag: item.logoTag,
          maxHeight: 150,
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 78, maxWidth: 440),
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

/// A "More Like This" row of similar titles at the foot of the detail page.
class _MoreLikeThis extends ConsumerWidget {
  final String itemId;
  const _MoreLikeThis({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarItemsProvider(itemId));
    // Show a section skeleton while loading instead of vanishing silently.
    if (similar.isLoading && !similar.hasValue) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(bottom: 24),
          child: SectionSkeleton(height: 324),
        ),
      );
    }
    final items = similar.asData?.value ?? const <BaseItemDto>[];
    if (items.isEmpty) return const SliverToBoxAdapter();
    final l = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: MediaSection(
          title: l.detailMoreLikeThis,
          height: 324,
          children: [
            for (final it in items)
              PosterCard(
                item: it,
                onTap: () => context.push('/item', extra: it),
              ),
          ],
        ),
      ),
    );
  }
}

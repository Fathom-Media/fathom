import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/cached_image.dart';
import '../widgets/detail_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_image.dart';
import '../widgets/meta_pill.dart';
import '../widgets/score_pills.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';

/// Offline downloads. A segmented control switches between the downloaded
/// library (posters, Movies + TV Shows) and the in-progress queue; the queue
/// tab only appears while something is downloading or has failed.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _seg = 0; // 0 = Downloaded (library), 1 = Downloading (queue)

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final downloads = ref.watch(downloadsProvider);
    final controller = ref.read(downloadsProvider.notifier);
    final all =
        downloads.asData?.value.values.toList() ?? const <DownloadEntry>[];
    final active =
        all.where((e) => e.status != DownloadStatus.complete).toList();
    final complete =
        all.where((e) => e.status == DownloadStatus.complete).toList();
    final showQueue = active.isNotEmpty;
    // No queue tab when nothing's in flight, so pin the view to the library.
    final seg = showQueue ? _seg : 0;
    final hasActiveTransfer =
        active.any((e) => e.status == DownloadStatus.downloading);

    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.ytDownloads),
        actions: [
          if (seg == 1 && hasActiveTransfer)
            TextButton.icon(
              onPressed: () => _confirmCancelAll(context, controller),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: Text(l.downloadsCancelAll),
            ),
        ],
      ),
      body: downloads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: '$e'),
        data: (map) {
          if (map.isEmpty) {
            return EmptyState(
              icon: Icons.download_rounded,
              title: l.ytNoDownloadsTitle,
              message: l.ytDownloadsScreenEmptyMessage,
            );
          }
          return Column(
            children: [
              if (showQueue)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.download_done_rounded, size: 18),
                        label: Text(l.detailDownloaded),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.downloading_rounded, size: 18),
                        label:
                            Text('${l.detailDownloading} (${active.length})'),
                      ),
                    ],
                    selected: {seg},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _seg = s.first),
                  ),
                ),
              Expanded(
                child: seg == 1
                    ? _DownloadQueue(items: active)
                    : _DownloadedLibrary(items: complete),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmCancelAll(
      BuildContext context, DownloadsController controller) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.downloadsCancelAll),
        content: Text(l.downloadsCancelAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.downloadsCancelAll),
          ),
        ],
      ),
    );
    if (ok == true) await controller.cancelActive();
  }
}

/// The in-progress/failed queue: a series' episodes grouped under one header,
/// movies and other single items on their own.
class _DownloadQueue extends StatelessWidget {
  final List<DownloadEntry> items;
  const _DownloadQueue({required this.items});

  @override
  Widget build(BuildContext context) {
    final series = <String, List<DownloadEntry>>{};
    final singles = <DownloadEntry>[];
    for (final e in items) {
      if (e.seriesId != null) {
        series.putIfAbsent(e.seriesId!, () => []).add(e);
      } else {
        singles.add(e);
      }
    }
    final rows = <Widget>[
      for (final g in series.entries)
        _SeriesGroupTile(seriesId: g.key, episodes: g.value),
      for (final e in singles) _DownloadTile(entry: e),
    ];
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => rows[i],
    );
  }
}

/// The downloaded-media library: a Movies section and a TV Shows section, each a
/// wrap of posters. A movie plays on tap; a show opens its episodes.
class _DownloadedLibrary extends ConsumerWidget {
  final List<DownloadEntry> items;
  const _DownloadedLibrary({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final movies = items.where((e) => e.seriesId == null).toList();
    final shows = <String, List<DownloadEntry>>{};
    for (final e in items.where((e) => e.seriesId != null)) {
      shows.putIfAbsent(e.seriesId!, () => []).add(e);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (movies.isNotEmpty) ...[
          _SectionHeader(l.detailMovies),
          _PosterGrid(children: [
            for (final e in movies)
              PosterCard(
                item: BaseItemDto(
                  id: e.itemId,
                  name: e.name,
                  type: e.type ?? 'Movie',
                  productionYear: e.year,
                  communityRating: e.communityRating,
                  criticRating: e.criticRating,
                  userData: UserItemData(played: e.played ?? false),
                ),
                localPosterPath: e.posterPath,
                contextActions: false,
                onMenu: () => _movieMenu(context, ref, e),
                onTap: () => context.push('/downloads/detail', extra: e.itemId),
              ),
          ]),
        ],
        if (shows.isNotEmpty) ...[
          if (movies.isNotEmpty) const SizedBox(height: 20),
          _SectionHeader(l.downloadsTvShows),
          _PosterGrid(children: [
            for (final g in shows.entries)
              PosterCard(
                item: BaseItemDto(
                  id: g.key,
                  name: g.value.first.seriesName ?? l.detailSeries,
                  type: 'Series',
                  productionYear: g.value.first.year,
                  communityRating: g.value.first.communityRating,
                  criticRating: g.value.first.criticRating,
                  userData: UserItemData(
                    unplayedItemCount: g.value.first.unplayedItemCount ?? 0,
                    played: g.value.first.played ?? false,
                  ),
                ),
                localPosterPath: g.value.first.posterPath,
                contextActions: false,
                onMenu: () => _showMenu(context, ref, g.key,
                    g.value.first.seriesName ?? l.detailSeries),
                onTap: () => context.push('/downloads/detail', extra: g.key),
              ),
          ]),
        ],
      ],
    );
  }

  void _movieMenu(BuildContext context, WidgetRef ref, DownloadEntry e) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuTitle(e.name),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l.actionShowDetails),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/downloads/detail', extra: e.itemId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(l.commonPlay),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/player',
                    extra: BaseItemDto(id: e.itemId, name: e.name));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(l.detailRemoveDownload,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(downloadsProvider.notifier).delete(e.itemId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMenu(
      BuildContext context, WidgetRef ref, String seriesId, String name) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuTitle(name),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l.actionShowDetails),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/downloads/detail', extra: seriesId);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(l.detailRemoveDownload,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text(l.detailRemoveDownload),
                    content: Text(l.detailRemoveOfflineCopy(name)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, false),
                        child: Text(l.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        child: Text(l.commonRemove),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref
                      .read(downloadsProvider.notifier)
                      .deleteSeries(seriesId);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// the downloaded library looks identical to browsing.
class _PosterGrid extends StatelessWidget {
  final List<Widget> children;
  const _PosterGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 18,
      children: [
        for (final c in children) SizedBox(height: 308, child: c),
      ],
    );
  }
}

/// A downloaded show's episodes, grouped by season, each playing on tap.
/// The item-name header at the top of a poster's action sheet.
class _MenuTitle extends StatelessWidget {
  final String text;
  const _MenuTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A downloaded item's cached full metadata (overview, cast, ratings, backdrop),
/// loaded from the file stashed at download time so the detail page works
/// offline. Null when it wasn't cached (older downloads).
final downloadDetailProvider =
    FutureProvider.family.autoDispose<BaseItemDto?, String>((ref, key) async {
  return ref.read(downloadsProvider.notifier).loadDetail(key);
});

/// The download detail page: the familiar library-detail layout (backdrop,
/// poster, meta, ratings, overview, cast) but scoped to the download folder —
/// ONLY the episodes you've downloaded, and every action removes the download
/// only, never the item on the server. Handles a movie or a series.
class DownloadDetailScreen extends ConsumerWidget {
  final String itemKey; // a movie's id, or a series' id
  const DownloadDetailScreen({super.key, required this.itemKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final controller = ref.read(downloadsProvider.notifier);
    final map = ref.watch(downloadsProvider).asData?.value ??
        const <String, DownloadEntry>{};
    final entries = map.values
        .where((e) =>
            e.status == DownloadStatus.complete &&
            (e.itemId == itemKey || e.seriesId == itemKey))
        .toList();
    if (entries.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final first = entries.first;
    final detail = ref.watch(downloadDetailProvider(itemKey)).asData?.value;
    final isSeries = detail?.isSeries ?? (first.seriesId != null);
    final item = detail ??
        BaseItemDto(
          id: itemKey,
          name: isSeries ? (first.seriesName ?? l.detailSeries) : first.name,
          type: isSeries ? 'Series' : (first.type ?? 'Movie'),
          productionYear: first.year,
          communityRating: first.communityRating,
          criticRating: first.criticRating,
        );

    final ratingPills = scorePills(
      rtCritic: item.criticRating?.round(),
      community: item.communityRating,
      prefs: prefs,
    );
    final metaLine = [
      isSeries ? l.detailSeries : l.detailMovie,
      if (item.productionYear != null) '${item.productionYear}',
      if (item.runtimeMinutes != null) fmtRuntime(item.runtimeMinutes!),
    ].join('  ·  ');

    Widget posterWidget() {
      final p = first.posterPath;
      if (p != null) {
        return Image.file(File(p),
            fit: BoxFit.cover, errorBuilder: (c, _, _) => MediaImage(item: item));
      }
      return MediaImage(item: item);
    }

    Future<void> remove() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(l.detailRemoveDownload),
          content: Text(l.detailRemoveOfflineCopy(item.name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: Text(l.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: Text(l.commonRemove)),
          ],
        ),
      );
      if (ok != true) return;
      if (isSeries) {
        await controller.deleteSeries(itemKey);
      } else {
        await controller.delete(itemKey);
      }
    }

    final slivers = <Widget>[
      SliverAppBar(
        expandedHeight: MediaQuery.sizeOf(context).height * 0.42,
        pinned: true,
        stretch: true,
        backgroundColor: scheme.surface,
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
                  alignment: const Alignment(0, -0.35)),
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
                poster: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: posterWidget()),
                title: Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black87)])),
                cert: item.officialRating != null
                    ? CertBadge(text: item.officialRating!)
                    : null,
                metaLine: metaLine,
                ratings: ratingPills,
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  HoverPillButton(
                    primary: true,
                    icon: Icons.play_arrow_rounded,
                    label: l.commonPlay,
                    onTap: () {
                      final play = isSeries ? entries.first : first;
                      context.push('/player',
                          extra: BaseItemDto(id: play.itemId, name: play.name));
                    },
                  ),
                  HoverPillButton(
                    icon: Icons.download_done_rounded,
                    label: l.detailRemoveDownload,
                    onTap: remove,
                  ),
                ],
              ),
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
                  children: [
                    for (final g in item.genres)
                      Chip(
                          label: Text(g),
                          visualDensity: VisualDensity.compact),
                  ],
                ),
              ],
              if (item.people.isNotEmpty) ...[
                const SizedBox(height: 20),
                _CastRow(people: item.people),
              ],
            ],
          ),
        ),
      ),
    ];

    if (isSeries) {
      final bySeason = <int, List<DownloadEntry>>{};
      for (final e in entries) {
        bySeason.putIfAbsent(e.seasonNumber ?? -1, () => []).add(e);
      }
      final seasons = bySeason.keys.toList()..sort();
      final realSeasons = seasons.where((s) => s >= 0).length;
      final epRows = <Widget>[const Divider(height: 1)];
      for (final s in seasons) {
        final seasonEps = bySeason[s]!
          ..sort((a, b) =>
              (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
        if (s >= 0 && (realSeasons > 1 || s > 0)) {
          epRows.add(_SeasonSubheader(
            label: s == 0 ? l.detailSpecials : l.detailSeasonNumber(s),
            onCancel: realSeasons > 1
                ? () => controller.deleteSeason(itemKey, s)
                : null,
          ));
        }
        for (final e in seasonEps) {
          epRows.add(ListTile(
            contentPadding: const EdgeInsets.only(left: 20, right: 8),
            leading: Icon(Icons.play_circle_outline_rounded,
                color: scheme.primary),
            title: Text(
              e.episodeNumber != null
                  ? 'E${e.episodeNumber}  ${e.name}'
                  : e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: l.commonRemove,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => controller.delete(e.itemId),
            ),
            onTap: () => context.push('/player',
                extra: BaseItemDto(id: e.itemId, name: e.name)),
          ));
        }
      }
      slivers.add(SliverList(delegate: SliverChildListDelegate(epRows)));
    }

    return Scaffold(body: CustomScrollView(slivers: slivers));
  }
}

/// A horizontal cast strip, like the library detail's. Photos load online and
/// fall back to a placeholder offline.
class _CastRow extends ConsumerWidget {
  final List<Person> people;
  const _CastRow({required this.people});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = people
        .where((p) => p.type == null || p.type == 'Actor' || p.type == 'GuestStar')
        .take(24)
        .toList();
    if (cast.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    Widget ph() => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.person_rounded, color: scheme.onSurfaceVariant));
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = cast[i];
          return SizedBox(
            width: 86,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 86,
                    height: 100,
                    child: (session != null && p.primaryImageTag != null)
                        ? CachedImage(
                            url: client.imageUrl(
                                baseUrl: session.baseUrl,
                                itemId: p.id,
                                type: 'Primary',
                                tag: p.primaryImageTag,
                                maxWidth: 180),
                            headers: headers,
                            errorBuilder: (_) => ph(),
                          )
                        : ph(),
                  ),
                ),
                const SizedBox(height: 6),
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                if (p.role != null && p.role!.isNotEmpty)
                  Text(p.role!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One download row: status glyph, name, progress/status, and a Cancel (while
/// downloading) / Remove (once done) button. A complete item plays on tap.
class _DownloadTile extends ConsumerWidget {
  final DownloadEntry entry;
  final bool indented;
  const _DownloadTile({required this.entry, this.indented = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(downloadsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final downloading = entry.status == DownloadStatus.downloading;
    final complete = entry.status == DownloadStatus.complete;
    final statusColor =
        entry.status == DownloadStatus.failed ? scheme.error : scheme.primary;
    return ListTile(
      contentPadding: EdgeInsets.only(left: indented ? 32 : 20, right: 12),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          switch (entry.status) {
            DownloadStatus.complete => Icons.download_done_rounded,
            DownloadStatus.downloading => Icons.downloading_rounded,
            DownloadStatus.failed => Icons.error_outline_rounded,
          },
          color: statusColor,
          size: 22,
        ),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: switch (entry.status) {
        DownloadStatus.downloading => LinearProgressIndicator(
            value: entry.progress > 0 ? entry.progress : null),
        DownloadStatus.failed => Text(l.ytFailed),
        DownloadStatus.complete => Text(l.ytAvailableOffline),
      },
      trailing: IconButton(
        tooltip: downloading ? l.downloadCancel : l.commonRemove,
        icon: Icon(
            downloading ? Icons.close_rounded : Icons.delete_outline_rounded),
        onPressed: () => controller.delete(entry.itemId),
      ),
      onTap: complete
          ? () => context.push('/player',
              extra: BaseItemDto(id: entry.itemId, name: entry.name))
          : null,
    );
  }
}

/// A series' episodes collapsed under one header: aggregate progress, a single
/// Cancel/Remove for the whole set, and the episodes revealed on expand.
class _SeriesGroupTile extends ConsumerWidget {
  final String seriesId;
  final List<DownloadEntry> episodes;
  const _SeriesGroupTile({required this.seriesId, required this.episodes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(downloadsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final total = episodes.length;
    final done =
        episodes.where((e) => e.status == DownloadStatus.complete).length;
    final active =
        episodes.where((e) => e.status == DownloadStatus.downloading).toList();
    final name = episodes.first.seriesName ?? l.detailSeries;
    final double? progress = active.isEmpty
        ? null
        : (done + active.fold<double>(0, (a, e) => a + e.progress)) / total;
    return ExpansionTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          active.isNotEmpty
              ? Icons.downloading_rounded
              : (done == total
                  ? Icons.download_done_rounded
                  : Icons.download_rounded),
          color: scheme.primary,
          size: 22,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: active.isNotEmpty ? l.downloadCancel : l.commonRemove,
            icon: Icon(active.isNotEmpty
                ? Icons.close_rounded
                : Icons.delete_outline_rounded),
            onPressed: () => controller.deleteSeries(seriesId),
          ),
        ],
      ),
      subtitle: active.isNotEmpty
          ? LinearProgressIndicator(value: progress)
          : Text('$done/$total'),
      tilePadding: const EdgeInsets.only(left: 20, right: 4),
      children: _seasonRows(l, controller),
    );
  }

  /// The expanded body: episodes grouped by season, each under a small season
  /// header ("Season 1"), so it's clear which season(s) are downloading. A
  /// single unnamed/unknown season is listed without a header. When a download
  /// spans more than one season, each header also carries a cancel/remove for
  /// just that season.
  List<Widget> _seasonRows(AppLocalizations l, DownloadsController controller) {
    final bySeason = <int, List<DownloadEntry>>{};
    for (final e in episodes) {
      bySeason.putIfAbsent(e.seasonNumber ?? -1, () => []).add(e);
    }
    final seasons = bySeason.keys.toList()..sort();
    final realSeasons = seasons.where((s) => s >= 0).length;
    final showHeaders =
        realSeasons > 1 || (realSeasons == 1 && seasons.any((s) => s > 0));
    final perSeasonCancel = realSeasons > 1;
    final rows = <Widget>[];
    for (final s in seasons) {
      final eps = bySeason[s]!
        ..sort(
            (a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
      if (showHeaders && s >= 0) {
        final active = eps.any((e) => e.status == DownloadStatus.downloading);
        rows.add(_SeasonSubheader(
          label: s == 0 ? l.detailSpecials : l.detailSeasonNumber(s),
          active: active,
          onCancel: perSeasonCancel
              ? () => controller.deleteSeason(seriesId, s)
              : null,
        ));
      }
      rows.addAll(eps.map((e) => _DownloadTile(entry: e, indented: true)));
    }
    return rows;
  }
}

/// A small season label between a series' episode groups on the Downloads
/// screen, with an optional per-season cancel/remove.
class _SeasonSubheader extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onCancel;
  const _SeasonSubheader(
      {required this.label, this.active = false, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 10, onCancel != null ? 4 : 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.primary,
              ),
            ),
          ),
          if (onCancel != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: active ? l.downloadCancel : l.commonRemove,
              icon: Icon(
                  active ? Icons.close_rounded : Icons.delete_outline_rounded,
                  size: 18),
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}

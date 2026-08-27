import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../state/downloads.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
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
                ),
                localPosterPath: e.posterPath,
                onMenu: () => _movieMenu(context, ref, e),
                onTap: () => context.push('/player',
                    extra: BaseItemDto(id: e.itemId, name: e.name)),
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
                ),
                localPosterPath: g.value.first.posterPath,
                onMenu: () => _showMenu(context, ref, g.key, g.value),
                onTap: () => _openShow(context, g.value),
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

  void _showMenu(BuildContext context, WidgetRef ref, String seriesId,
      List<DownloadEntry> episodes) {
    final l = AppLocalizations.of(context);
    final name = episodes.first.seriesName ?? l.detailSeries;
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
              leading: const Icon(Icons.list_rounded),
              title: Text(l.detailEpisodes),
              onTap: () {
                Navigator.pop(ctx);
                _openShow(context, episodes);
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

  void _openShow(BuildContext context, List<DownloadEntry> episodes) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ShowEpisodesSheet(episodes: episodes),
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

/// Lays out full-size (176-wide) poster cards in a wrap, each height-bounded so
/// the card's flexible poster resolves. Same card the rest of the app uses, so
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
class _ShowEpisodesSheet extends StatelessWidget {
  final List<DownloadEntry> episodes;
  const _ShowEpisodesSheet({required this.episodes});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = episodes.first.seriesName ?? l.detailSeries;
    final bySeason = <int, List<DownloadEntry>>{};
    for (final e in episodes) {
      bySeason.putIfAbsent(e.seasonNumber ?? -1, () => []).add(e);
    }
    final seasons = bySeason.keys.toList()..sort();
    final rows = <Widget>[];
    for (final s in seasons) {
      final eps = bySeason[s]!
        ..sort(
            (a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
      if (s >= 0 &&
          (seasons.where((x) => x >= 0).length > 1 || s > 0)) {
        rows.add(_SeasonSubheader(
            label: s == 0 ? l.detailSpecials : l.detailSeasonNumber(s)));
      }
      for (final e in eps) {
        rows.add(ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(Icons.play_circle_outline_rounded,
              color: Theme.of(context).colorScheme.primary),
          title: Text(
            e.episodeNumber != null ? 'E${e.episodeNumber}  ${e.name}' : e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.pop(context);
            context.push('/player',
                extra: BaseItemDto(id: e.itemId, name: e.name));
          },
        ));
      }
    }
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            ...rows,
          ],
        ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../state/downloads.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';

/// Offline downloads: play, see progress, or remove downloaded items.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final downloads = ref.watch(downloadsProvider);
    final controller = ref.read(downloadsProvider.notifier);
    final hasActive = (downloads.asData?.value.values ?? const [])
        .any((e) => e.status == DownloadStatus.downloading);

    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.ytDownloads),
        actions: [
          if (hasActive)
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
          final entries = map.values.toList();
          if (entries.isEmpty) {
            return EmptyState(
              icon: Icons.download_rounded,
              title: l.ytNoDownloadsTitle,
              message: l.ytDownloadsScreenEmptyMessage,
            );
          }
          // A series' episodes collapse under one header; movies and other
          // single items stand on their own.
          final series = <String, List<DownloadEntry>>{};
          final singles = <DownloadEntry>[];
          for (final e in entries) {
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

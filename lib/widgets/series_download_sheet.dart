import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';

/// Opens the download-scope picker for a [series]: Download All, or a single
/// season. Resolves the episodes first (cached by [episodesProvider]) and groups
/// them by season. A single-season series has nothing to choose, so it skips the
/// sheet and downloads everything directly. Shared by the detail page's download
/// button and the item context menu, so the same choice appears wherever a
/// series is downloaded.
Future<void> showSeriesDownloadSheet(
    BuildContext context, BaseItemDto series, {String? asType}) async {
  // Read through the app-wide container, not a caller's ref, so the fetch and
  // the single-season download survive the caller (a grid card, a menu)
  // unmounting mid-request.
  final container = ProviderScope.containerOf(context, listen: false);
  List<BaseItemDto> episodes;
  try {
    episodes = await container.read(episodesProvider(series.id).future);
  } catch (_) {
    episodes = const [];
  }
  if (!context.mounted || episodes.isEmpty) return;

  final seasons = <int, List<BaseItemDto>>{};
  for (final e in episodes) {
    seasons.putIfAbsent(e.parentIndexNumber ?? 0, () => []).add(e);
  }
  // Nothing to pick from with a single season: download it all.
  if (seasons.length <= 1) {
    await container
        .read(downloadsProvider.notifier)
        .downloadEpisodes(episodes, asType: asType);
    return;
  }
  final ordered = {
    for (final n in seasons.keys.toList()..sort()) n: seasons[n]!,
  };

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SeriesDownloadSheet(
      title: series.name,
      allEpisodes: episodes,
      seasons: ordered,
      asType: asType,
    ),
  );
}

class _SeriesDownloadSheet extends ConsumerWidget {
  final String title;
  final List<BaseItemDto> allEpisodes;
  final Map<int, List<BaseItemDto>> seasons;
  final String? asType;

  const _SeriesDownloadSheet({
    required this.title,
    required this.allEpisodes,
    required this.seasons,
    this.asType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final map = ref.watch(downloadsProvider).asData?.value ?? const {};

    Widget row(String label, List<BaseItemDto> eps, {bool bold = false}) {
      var done = 0;
      var downloading = 0;
      for (final e in eps) {
        final s = map[e.id]?.status;
        if (s == DownloadStatus.complete) {
          done++;
        } else if (s == DownloadStatus.downloading) {
          downloading++;
        }
      }
      final all = done == eps.length;
      final Widget trailing;
      if (all) {
        trailing = Icon(Icons.download_done_rounded,
            color: Theme.of(context).colorScheme.primary);
      } else if (downloading > 0) {
        trailing = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      } else {
        trailing = const Icon(Icons.download_rounded);
      }
      return ListTile(
        title: Text(label,
            style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
        subtitle: Text('$done/${eps.length}'),
        trailing: trailing,
        // Already-complete episodes are skipped, so tapping a fully-downloaded
        // scope is a harmless no-op; tapping a partial one grabs the rest.
        onTap: all
            ? null
            : () => ref
                .read(downloadsProvider.notifier)
                .downloadEpisodes(eps, asType: asType),
      );
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
            row(l.downloadAll, allEpisodes, bold: true),
            for (final entry in seasons.entries)
              row(
                entry.key == 0
                    ? l.detailSpecials
                    : l.detailSeasonNumber(entry.key),
                entry.value,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

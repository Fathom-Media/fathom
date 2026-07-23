import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../state/downloads.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../l10n/generated/app_localizations.dart';

/// Offline downloads: play, see progress, or remove downloaded items.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final downloads = ref.watch(downloadsProvider);
    final controller = ref.read(downloadsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l.ytDownloads)),
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
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              final complete = e.status == DownloadStatus.complete;
              final scheme = Theme.of(context).colorScheme;
              final statusColor = switch (e.status) {
                DownloadStatus.complete => scheme.primary,
                DownloadStatus.downloading => scheme.primary,
                DownloadStatus.failed => scheme.error,
              };
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    switch (e.status) {
                      DownloadStatus.complete => Icons.download_done_rounded,
                      DownloadStatus.downloading => Icons.downloading_rounded,
                      DownloadStatus.failed => Icons.error_outline_rounded,
                    },
                    color: statusColor,
                    size: 22,
                  ),
                ),
                title: Text(e.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: switch (e.status) {
                  DownloadStatus.downloading => LinearProgressIndicator(
                      value: e.progress > 0 ? e.progress : null),
                  DownloadStatus.failed => Text(l.ytFailed),
                  DownloadStatus.complete => Text(l.ytAvailableOffline),
                },
                trailing: IconButton(
                  tooltip: l.commonRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => controller.delete(e.itemId),
                ),
                onTap: complete
                    ? () => context.push('/player',
                        extra: BaseItemDto(id: e.itemId, name: e.name))
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/youtube_download.dart';
import '../services/tv_mode.dart';
import '../state/downloads.dart';
import '../state/youtube_providers.dart';

/// Floating pills for downloads in flight: one for Jellyfin media, one for
/// YouTube, stacked bottom-center so both can show at once without
/// overlapping. Each renders nothing when its own system is idle. Hidden on
/// TV (downloads there are rare and the D-pad has no use for a floating tap
/// target).
class DownloadPills extends ConsumerWidget {
  const DownloadPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isTvDevice) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final jellyfin = ref.watch(downloadsProvider).asData?.value ?? const {};
    final jellyfinActive = [
      for (final e in jellyfin.values)
        if (e.status == DownloadStatus.downloading) e,
    ];
    // Overall progress: the mean of each item's progress. Indeterminate until
    // at least one item reports a fraction (a fresh queue sits at 0).
    final jellyfinMeasured =
        jellyfinActive.where((e) => e.progress > 0).toList();
    final double? jellyfinProgress = jellyfinMeasured.isEmpty
        ? null
        : jellyfinMeasured.fold<double>(0, (a, e) => a + e.progress) /
            jellyfinActive.length;

    final youtube = ref.watch(youtubeDownloadsProvider).asData?.value ??
        const <YoutubeDownload>[];
    final youtubeActive = [for (final d in youtube) if (d.isActive) d];
    final youtubeMeasured =
        youtubeActive.where((d) => (d.progress ?? 0) > 0).toList();
    final double? youtubeProgress = youtubeMeasured.isEmpty
        ? null
        : youtubeMeasured.fold<double>(0, (a, d) => a + (d.progress ?? 0)) /
            youtubeActive.length;

    if (jellyfinActive.isEmpty && youtubeActive.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (jellyfinActive.isNotEmpty)
              _Pill(
                label: l.detailDownloading,
                progress: jellyfinProgress,
                scheme: scheme,
                onTap: () => context.push('/downloads'),
              ),
            if (jellyfinActive.isNotEmpty && youtubeActive.isNotEmpty)
              const SizedBox(height: 8),
            if (youtubeActive.isNotEmpty)
              _Pill(
                label: l.ytDownloadPill,
                progress: youtubeProgress,
                scheme: scheme,
                onTap: () =>
                    context.push('/youtube', extra: kYoutubeDownloadsTabIndex),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final double? progress;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.progress,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.primaryContainer,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.6,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (progress != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${(progress! * 100).round()}%',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

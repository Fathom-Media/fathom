import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';
import '../state/downloads.dart';

/// A floating pill that appears whenever one or more downloads are in flight,
/// showing how many and the overall progress. Tapping it opens the Downloads
/// screen, where each (or all) can be cancelled. Renders nothing when nothing is
/// downloading, and is hidden on TV (downloads there are rare and the D-pad has
/// no use for a floating tap target).
class DownloadPill extends ConsumerWidget {
  const DownloadPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isTvDevice) return const SizedBox.shrink();
    final map = ref.watch(downloadsProvider).asData?.value ?? const {};
    final active = [
      for (final e in map.values)
        if (e.status == DownloadStatus.downloading) e,
    ];
    if (active.isEmpty) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Overall progress: the mean of each item's progress. Indeterminate until at
    // least one item reports a fraction (a fresh queue sits at 0).
    final measured = active.where((e) => e.progress > 0).toList();
    final double? overall = measured.isEmpty
        ? null
        : measured.fold<double>(0, (a, e) => a + e.progress) / active.length;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          color: scheme.primaryContainer,
          elevation: 3,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/downloads'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: overall,
                      strokeWidth: 2.6,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.detailDownloading,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (overall != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(overall * 100).round()}%',
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
        ),
      ),
    );
  }
}

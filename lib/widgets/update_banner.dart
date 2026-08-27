import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import '../state/updates.dart';

/// A slim banner across the top of the app when a newer release is available,
/// with a shortcut to the Updates screen and a per-version dismiss. Mirrors the
/// in-app update prompt other apps show, and complements the persistent nav-rail
/// indicator (which stays, so the reminder isn't lost after a dismiss). Renders
/// nothing when up to date, dismissed for this version, or on TV.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isTvDevice) return const SizedBox.shrink();
    final status = ref.watch(updateControllerProvider).asData?.value;
    if (status == null || !status.updateAvailable) return const SizedBox.shrink();
    final prefs = ref.watch(preferencesProvider).asData?.value;
    final version = status.latest!.version;
    if (prefs != null && prefs.updateBannerDismissedVersion == version) {
      return const SizedBox.shrink();
    }

    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.system_update_rounded,
                  size: 20, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.updateAvailableHeadline(version),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/updates'),
                child: Text(l.updateBannerAction),
              ),
              IconButton(
                tooltip: l.updateBannerDismiss,
                iconSize: 20,
                color: scheme.onPrimaryContainer,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => ref
                    .read(preferencesProvider.notifier)
                    .edit((p) => p.copyWith(updateBannerDismissedVersion: version)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

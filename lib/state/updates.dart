import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../services/app_updates.dart';
import 'notifications_controller.dart';
import 'preferences.dart';

/// The result of an update check: the running version and the newest release
/// found for the active channel (null if none / the check failed).
class UpdateStatus {
  final String currentVersion;
  final GithubRelease? latest;
  const UpdateStatus({required this.currentVersion, this.latest});

  bool get updateAvailable =>
      latest != null && compareSemver(latest!.version, currentVersion) > 0;
}

/// Checks GitHub for a newer release. Runs once per launch (from the rail
/// indicator) and on demand from the Updates screen. One call per launch is
/// well within GitHub's unauthenticated rate limit for a desktop app.
class UpdateController extends AsyncNotifier<UpdateStatus?> {
  @override
  Future<UpdateStatus?> build() async => null;

  Future<void> check({bool force = false}) async {
    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs == null) return; // prefs not loaded yet; retry next trigger
    if (state.isLoading && !force) return; // a check is already in flight

    state = const AsyncLoading<UpdateStatus?>();
    state = await AsyncValue.guard(() async {
      final info = await PackageInfo.fromPlatform();
      final current = info.version.isNotEmpty ? info.version : '0.9.0';
      final latest = await fetchLatestRelease(
          includePrereleases: prefs.updateChannel == 'beta');
      final status = UpdateStatus(currentVersion: current, latest: latest);
      await _notifyOnce(prefs, status);
      return status;
    });
  }

  /// Posts a single in-app notification the first time a given newer version is
  /// seen (the persistent rail indicator carries the ongoing reminder). Deep
  /// links to the Updates screen.
  Future<void> _notifyOnce(Prefs prefs, UpdateStatus status) async {
    if (!status.updateAvailable) return;
    final version = status.latest!.version;
    if (prefs.updateNotifiedVersion == version) return; // already surfaced
    await ref
        .read(preferencesProvider.notifier)
        .edit((x) => x.copyWith(updateNotifiedVersion: version));
    await pushAppNotification(
      ref,
      kind: AppNotifKind.updateAvailable,
      title: tr.updateNotifTitle(version),
      body: tr.updateNotifBody,
      enabled: prefs.notifUpdates,
      // Also raise an Android system notification so a new build is visible
      // outside the app (the in-app bell alone is easy to miss on mobile).
      osNotifyMobile: true,
      route: '/updates',
    );
  }
}

final updateControllerProvider =
    AsyncNotifierProvider<UpdateController, UpdateStatus?>(
        UpdateController.new);

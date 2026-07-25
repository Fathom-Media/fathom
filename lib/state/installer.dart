import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_installer.dart';
import '../services/app_updates.dart';

/// Download + install progress for the Updates screen.
class InstallProgress {
  final bool busy;
  final double progress; // 0..1 during download
  final String? error;
  const InstallProgress({this.busy = false, this.progress = 0, this.error});
}

/// Drives the in-app self-update: download the platform asset with progress,
/// then replace + relaunch (which ends this process). Surfaces any pre-relaunch
/// failure as [InstallProgress.error].
class InstallController extends Notifier<InstallProgress> {
  @override
  InstallProgress build() => const InstallProgress();

  Future<void> install(ReleaseAsset asset) async {
    if (state.busy) return;
    state = const InstallProgress(busy: true);
    try {
      await downloadAndInstall(asset,
          onProgress: (p) => state = InstallProgress(busy: true, progress: p));
      // On success the process is replaced by a fresh launch and never gets
      // here; returning just means nothing more to do.
    } catch (e) {
      state = InstallProgress(error: e.toString());
    }
  }
}

final installControllerProvider =
    NotifierProvider<InstallController, InstallProgress>(InstallController.new);

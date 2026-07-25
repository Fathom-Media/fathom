import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'app_updates.dart';

/// Downloads a release asset and installs it in place, then relaunches Fathom.
///
/// Linux (AppImage): downloads the new AppImage beside the running one, makes it
/// executable, renames it over `$APPIMAGE` (the live process keeps the old inode
/// until it exits), relaunches, and quits. Windows (portable zip): downloads the
/// zip, hands a helper PowerShell script the job of waiting for this process to
/// exit, extracting over the app folder, and relaunching, since Windows locks a
/// running exe.
///
/// [onProgress] reports 0..1 during download. This never returns on success: the
/// process is replaced by a fresh launch. Throws on a failure before that point.
Future<void> downloadAndInstall(
  ReleaseAsset asset, {
  void Function(double progress)? onProgress,
}) async {
  if (Platform.isLinux) return _installLinuxAppImage(asset, onProgress);
  if (Platform.isWindows) return _installWindowsZip(asset, onProgress);
  throw UnsupportedError('In-app install is not supported on this platform.');
}

void _report(void Function(double)? cb, int received, int total) {
  if (cb != null && total > 0) cb(received / total);
}

Future<void> _installLinuxAppImage(
    ReleaseAsset asset, void Function(double)? onProgress) async {
  final appImage = Platform.environment['APPIMAGE'];
  if (appImage == null || appImage.isEmpty) {
    throw StateError('Not running as an AppImage.');
  }
  final staged = '$appImage.new';
  final dio = Dio();
  await dio.download(asset.url, staged,
      onReceiveProgress: (r, t) => _report(onProgress, r, t));

  await Process.run('chmod', ['+x', staged]);
  // Atomic replace (same directory), then relaunch the new file detached and
  // exit so the old, still-mounted image is released.
  await File(staged).rename(appImage);
  await Process.start(appImage, const [],
      mode: ProcessStartMode.detached);
  exit(0);
}

Future<void> _installWindowsZip(
    ReleaseAsset asset, void Function(double)? onProgress) async {
  final appDir = File(Platform.resolvedExecutable).parent.path;
  final tmp = await getTemporaryDirectory();
  final zipPath = '${tmp.path}\\fathom_update.zip';
  final scriptPath = '${tmp.path}\\fathom_update.ps1';
  final extractDir = '${tmp.path}\\fathom_update_extract';

  final dio = Dio();
  await dio.download(asset.url, zipPath,
      onReceiveProgress: (r, t) => _report(onProgress, r, t));

  // The zip contains a top-level "Fathom" folder (see the release packaging).
  final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
while (Get-Process -Id $pid) { Start-Sleep -Milliseconds 300 }
Remove-Item '$extractDir' -Recurse -Force
Expand-Archive -Path '$zipPath' -DestinationPath '$extractDir' -Force
Copy-Item (Join-Path '$extractDir' 'Fathom\\*') -Destination '$appDir' -Recurse -Force
Start-Process -FilePath (Join-Path '$appDir' 'fathom.exe')
Remove-Item '$zipPath' -Force
Remove-Item '$extractDir' -Recurse -Force
Remove-Item '$scriptPath' -Force
''';
  await File(scriptPath).writeAsString(script);
  await Process.start(
    'powershell',
    [
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      scriptPath,
    ],
    mode: ProcessStartMode.detached,
  );
  exit(0);
}

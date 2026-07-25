import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_updates.dart';
import 'secure_http.dart';

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
  final dio = await secureDio();
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
  // Log beside the exe (a path we know exactly) so it's unambiguous where to
  // look, path_provider's temp dir isn't always %TEMP%.
  final logPath = '$appDir\\fathom_update.log';

  final dio = await secureDio();
  await dio.download(asset.url, zipPath,
      onReceiveProgress: (r, t) => _report(onProgress, r, t));

  // A helper that waits for this process to exit, extracts the new build over
  // the app folder, and relaunches. Windows locks a running exe, hence the
  // wait. Every step is logged to fathom_update.log for diagnosis, with a
  // timeout so a stuck wait can't hang forever, and a fallback for the zip's
  // top-level folder (release zips wrap files in "Fathom", CI zips don't).
  final script = '''
\$log = '$logPath'
function Log(\$m) { "[\$(Get-Date -Format o)] \$m" | Out-File -FilePath \$log -Append -Encoding utf8 }
Log "start; waiting for PID $pid"
\$n = 0
while ((Get-Process -Id $pid -ErrorAction SilentlyContinue) -and (\$n -lt 200)) { Start-Sleep -Milliseconds 300; \$n++ }
Log "wait done (n=\$n)"
try {
  if (Test-Path '$extractDir') { Remove-Item '$extractDir' -Recurse -Force }
  Log "extracting '$zipPath'"
  Expand-Archive -Path '$zipPath' -DestinationPath '$extractDir' -Force
  \$src = Join-Path '$extractDir' 'Fathom'
  if (-not (Test-Path \$src)) { \$src = '$extractDir' }
  Log "copying from \$src to '$appDir'"
  Copy-Item (Join-Path \$src '*') -Destination '$appDir' -Recurse -Force
  Log "relaunching"
  Start-Process -FilePath (Join-Path '$appDir' 'fathom.exe') -WorkingDirectory '$appDir'
  Log "done"
} catch {
  Log "ERROR: \$_"
}
Remove-Item '$zipPath' -Force -ErrorAction SilentlyContinue
Remove-Item '$extractDir' -Recurse -Force -ErrorAction SilentlyContinue
''';
  await File(scriptPath).writeAsString(script);
  await Process.start(
    'powershell',
    [
      '-NoProfile',
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

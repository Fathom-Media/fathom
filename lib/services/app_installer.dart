import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:open_filex/open_filex.dart';
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
  if (Platform.isAndroid) return _installAndroidApk(asset, onProgress);
  throw UnsupportedError('In-app install is not supported on this platform.');
}

/// Android: download the APK and hand it to the system package installer. This
/// does NOT replace-and-relaunch like desktop; the OS shows its install prompt
/// (the user grants "install unknown apps" once), so we return normally and let
/// the installer take over.
Future<void> _installAndroidApk(
    ReleaseAsset asset, void Function(double)? onProgress) async {
  final dir = await getExternalStorageDirectory() ??
      await getTemporaryDirectory();
  final apkPath = '${dir.path}/fathom_update.apk';
  final dio = await secureDio();
  await dio.download(asset.url, apkPath,
      onReceiveProgress: (r, t) => _report(onProgress, r, t));
  await _verifyDownload(apkPath, asset); // reject a truncated apk
  final result = await OpenFilex.open(
    apkPath,
    type: 'application/vnd.android.package-archive',
  );
  if (result.type != ResultType.done) {
    throw StateError('Could not open the installer: ${result.message}');
  }
}

void _report(void Function(double)? cb, int received, int total) {
  if (cb != null && total > 0) cb(received / total);
}

/// Guards the swap-in: fails (and deletes the bad file) if the download doesn't
/// match the release asset's expected size, or — on Linux, [checkElf] — isn't an
/// ELF for this machine's architecture. This is what stops a truncated download
/// (a mid-upload grab) or a wrong-architecture AppImage (an older updater that
/// fetched the aarch64 build onto an x86_64 host) from being renamed over the
/// running app and bricking it: on any mismatch the current version is kept and
/// a readable error is surfaced instead.
Future<void> _verifyDownload(String path, ReleaseAsset asset,
    {bool checkElf = false}) async {
  final file = File(path);
  Future<Never> fail(String why) async {
    try {
      await file.delete();
    } catch (_) {}
    throw StateError('$why Your current version was kept.');
  }

  final len = await file.length();
  if (asset.size > 0 && len != asset.size) {
    await fail('The update download was incomplete '
        '($len of ${asset.size} bytes).');
  }
  if (!checkElf) return;

  // Read just the ELF header: magic (0x7F 'E' 'L' 'F') then e_machine at
  // offset 18 (2 bytes, little-endian; both arches are LE).
  final head = <int>[];
  await for (final chunk in file.openRead(0, 20)) {
    head.addAll(chunk);
  }
  final isElf = head.length >= 20 &&
      head[0] == 0x7F &&
      head[1] == 0x45 &&
      head[2] == 0x4C &&
      head[3] == 0x46;
  if (!isElf) {
    await fail('The update download was not a valid application file.');
  }
  const emX8664 = 0x3E; // EM_X86_64
  const emAarch64 = 0xB7; // EM_AARCH64
  final machine = head[18] | (head[19] << 8);
  final want = Abi.current() == Abi.linuxArm64 ? emAarch64 : emX8664;
  if (machine != want) {
    final got = machine == emAarch64
        ? 'ARM64'
        : (machine == emX8664
            ? 'x86_64'
            : '0x${machine.toRadixString(16)}');
    await fail('The update download was for the wrong architecture ($got).');
  }
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

  // Never rename a truncated or wrong-arch file over the running AppImage.
  await _verifyDownload(staged, asset, checkElf: true);
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
  final logPath = '${tmp.path}\\fathom_update.log'; // for support diagnosis

  final dio = await secureDio();
  await dio.download(asset.url, zipPath,
      onReceiveProgress: (r, t) => _report(onProgress, r, t));
  await _verifyDownload(zipPath, asset); // reject a truncated zip

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

  // Launch through `cmd /c start` so the helper is an independent process that
  // survives this one exiting (a plain detached child can be torn down with the
  // parent), while staying in the interactive session so the relaunched window
  // appears.
  await Process.start(
    'cmd.exe',
    [
      '/c',
      'start',
      '',
      'powershell',
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

import 'dart:io';

/// When running as a Linux AppImage, install a `.desktop` entry and hicolor
/// icons into the user's data dir on first run.
///
/// Why: on Wayland (KWin, Mutter) the taskbar/switcher icon is not the GTK
/// window icon, it is resolved by matching the window's app-id to an installed
/// `.desktop` file's `Icon=`. A bare AppImage isn't desktop-integrated, so the
/// compositor finds no match and shows a generic fallback. Writing the entry
/// (pointing `Exec` at the AppImage itself) and copying the icons fixes it, and
/// also gives the app a normal launcher entry.
///
/// Best-effort and idempotent: it only rewrites when the entry changed, and any
/// failure is swallowed so it can never break startup. No-op unless running as
/// an AppImage.
Future<void> integrateAppImageDesktopEntry() async {
  if (!Platform.isLinux) return;
  final env = Platform.environment;
  final appImage = env['APPIMAGE']; // set only inside a running AppImage
  final appDir = env['APPDIR']; // the mounted AppImage root
  final home = env['HOME'];
  if (appImage == null || appImage.isEmpty || home == null || home.isEmpty) {
    return;
  }

  const appId = 'app.fathom.player';
  try {
    final dataHome = (env['XDG_DATA_HOME']?.isNotEmpty ?? false)
        ? env['XDG_DATA_HOME']!
        : '$home/.local/share';

    // 1. Copy the hicolor icons out of the AppDir so the theme resolves
    //    Icon=app.fathom.player at every size.
    var installedIcon = false;
    if (appDir != null && appDir.isNotEmpty) {
      for (final size in const ['16', '32', '48', '64', '128', '256', '512']) {
        final src = File(
            '$appDir/usr/share/icons/hicolor/${size}x$size/apps/$appId.png');
        if (src.existsSync()) {
          final destDir =
              Directory('$dataHome/icons/hicolor/${size}x$size/apps');
          destDir.createSync(recursive: true);
          src.copySync('${destDir.path}/$appId.png');
          installedIcon = true;
        }
      }
    }

    // 2. Write the launcher entry, Exec pointing at the AppImage path.
    final appsDir = Directory('$dataHome/applications');
    appsDir.createSync(recursive: true);
    final desktopFile = File('${appsDir.path}/$appId.desktop');
    final desktop = '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Fathom\n'
        'GenericName=Media Player\n'
        'Comment=A modern Jellyfin client\n'
        'Exec="$appImage" %U\n'
        'Icon=$appId\n'
        'Terminal=false\n'
        'Categories=AudioVideo;Video;Player;\n'
        'StartupWMClass=$appId\n';

    // Only rewrite when it changed, so caches aren't rebuilt on every launch.
    var changed = false;
    if (!desktopFile.existsSync() ||
        desktopFile.readAsStringSync() != desktop) {
      desktopFile.writeAsStringSync(desktop);
      changed = true;
    }

    // Clear any duplicate launcher an external AppImage integrator
    // (AppImageLauncher / appimaged) previously created for this app, e.g.
    // `appimagekit_<hash>-app.fathom.player.desktop`. Two entries both named
    // "Fathom" is what produced the duplicate launcher icon in issue #28. The
    // embedded desktop now carries X-AppImage-Integrate=false so integrators
    // stand down going forward; this clears any straggler from before the fix.
    for (final e in appsDir.listSync()) {
      if (e is! File) continue;
      final base = e.path.split('/').last;
      if (base != '$appId.desktop' &&
          base.contains(appId) &&
          base.toLowerCase().contains('appimagekit')) {
        try {
          e.deleteSync();
          changed = true;
        } catch (_) {}
      }
    }

    if (changed) {
      await Process.run('update-desktop-database', [appsDir.path]);
      if (installedIcon) {
        await Process.run(
            'gtk-update-icon-cache', ['-f', '$dataHome/icons/hicolor']);
      }
    }
  } catch (_) {
    // Desktop integration is a nicety; never let it break startup.
  }
}

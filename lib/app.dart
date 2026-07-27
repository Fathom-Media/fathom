import 'dart:io' show Platform, exit;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'routing/app_router.dart';
import 'services/diagnostics.dart';
import 'services/live_players.dart';
import 'services/live_streams.dart';
import 'services/notifications.dart';
import 'state/syncplay_session.dart';
import 'state/mpris_integration.dart';
import 'state/pip_controller.dart';
import 'state/popout_controller.dart';
import 'state/preferences.dart';
import 'state/server_address.dart';
import 'theme/app_theme.dart';
import 'widgets/app_snack.dart';
import 'widgets/popout_video.dart';
import 'widgets/window_frame.dart';

/// Lets a mouse and trackpad drag-scroll, not just touch. Without this, the
/// horizontal rows (Discover, Home) can't be scrolled at all on desktop, so
/// only the first few tiles are ever reachable.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  // Momentum-based scrolling with a soft overscroll, so every list feels
  // buttery and consistent across platforms rather than the abrupt desktop
  // clamp.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
          parent: RangeMaintainingScrollPhysics());
}

class FathomApp extends ConsumerStatefulWidget {
  const FathomApp({super.key});

  @override
  ConsumerState<FathomApp> createState() => _FathomAppState();
}

class _FathomAppState extends ConsumerState<FathomApp> with WindowListener {
  /// Last rites before the process goes.
  ///
  /// mpv is torn down while the Flutter engine is still alive: closing the
  /// window with playback running crashed on the way out, because the engine
  /// goes first and media_kit's video output then unregisters its texture
  /// against an engine that no longer exists. Screens dispose their own player,
  /// but quitting outright skips that, and the app-wide audio player hangs off
  /// a root provider whose onDispose never runs.
  ///
  /// Two exit paths need catching. [AppLifecycleListener.onExitRequested] covers
  /// the framework's own exit flow. [onWindowClose] covers window_manager's
  /// close (the custom titlebar X calls windowManager.close(), and Alt+F4 / the
  /// compositor route through here too) — main.dart sets preventClose so those
  /// land here instead of destroying the window immediately.
  ///
  /// Live TV streams are handed back for a blunter reason: a tuner is physical.
  /// Jellyfin holds one open until told otherwise, so quitting mid-channel pins
  /// it until the server restarts, and the next tune-in 500s.
  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await _teardown();
      return AppExitResponse.exit;
    },
  );

  bool _tearingDown = false;

  Future<void> _teardown() async {
    if (_tearingDown) return;
    _tearingDown = true;
    // Close the SyncPlay socket + cancel its timers first, so no scheduled
    // command or keepalive fires against a half-torn-down tree during exit.
    try {
      await ref.read(syncPlaySessionProvider).disconnect();
    } catch (_) {}
    await LiveStreams.closeAll();
    await LivePlayers.disposeAll();
    // A player handed to the picture-in-picture dock is taken off the
    // LivePlayers list; it's normally disposed by the pip provider's onDispose,
    // which never runs at process exit. Dispose it here so quitting with a
    // mini-player playing doesn't segfault in mpv's teardown.
    try {
      final pip = ref.read(pipProvider.notifier);
      final p = pip.player;
      if (p != null) {
        pip.player = null;
        await p.stop();
        await p.dispose();
      }
    } catch (_) {}
    // Let libmpv/the video output drain its in-flight callbacks and release its
    // Flutter textures before the engine tears down its views — otherwise the
    // texture unregisters against an engine that is already gone (the
    // "Callback invoked after it has been deleted" / RemoveView crash on close).
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  void initState() {
    super.initState();
    _lifecycle; // create the listener
    if (_isDesktop) windowManager.addListener(this);
    // Android 13+: request the notification permission once the first frame is
    // up (needs a resumed Activity). Without it every notification — including
    // the media-playback controls — is silently blocked.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNotifications.requestPermission();
      });
      // Draw edge-to-edge with transparent system bars (required behaviour on
      // Android 15+, and a cleaner look elsewhere): the app paints behind the
      // status and gesture-nav bars, and SafeArea insets the content. No forced
      // nav-bar contrast scrim; AppBars still set their own icon brightness.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ));
    }
  }

  @override
  void onWindowClose() async {
    await _teardown();
    // Windows stalls, and Linux SEGFAULTS, finalizing the Flutter engine +
    // libmpv on a normal window destroy: media_kit's video output races the
    // view removal (FlutterEngineRemoveView / "message handler without an
    // engine"). SyncPlay is disconnected and every player disposed above, so
    // terminate the process directly instead of grinding through that teardown.
    // macOS destroys the window normally.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) exit(0);
    await windowManager.destroy();
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Keep the desktop media integration (MPRIS) alive for the app's lifetime.
    ref.watch(mprisProvider);
    // Keep the internal/external address resolver alive (no-op unless the
    // active account has both addresses configured).
    ref.watch(serverAddressResolverProvider);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    // Mirror the diagnostic-logging pref into the app-wide capture flag, so
    // global error hooks and app logs record from launch when it's on.
    Diagnostics.instance.enabled = prefs.diagnosticLogging;
    final accent = Color(prefs.accentColor);
    final mode = switch (prefs.themeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'Fathom',
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent, amoled: prefs.amoled),
      themeMode: mode,
      routerConfig: router,
      scrollBehavior: _AppScrollBehavior(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Scaffolds are transparent (so the shell's ambient wash pervades the
      // app); this paints the solid base beneath everything.
      builder: (context, child) {
        // Record the resolved locale so no-context code (the notification layer)
        // can translate via `tr`. Safe here: the builder runs under Localizations.
        activeLocale = Localizations.localeOf(context);
        return Consumer(
        builder: (context, ref, _) {
          final poppedOut = ref.watch(popoutProvider);
          return Stack(
            children: [
              WindowFrame(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: child ?? const SizedBox(),
                ),
              ),
              // The desktop pop-out fills the (shrunken) window over everything.
              // Wrapped in its own Overlay because this builder sits outside the
              // router's Navigator, and tooltips need an Overlay ancestor.
              if (poppedOut)
                Positioned.fill(
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => const Material(
                          color: Colors.black,
                          child: PopoutVideo(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        );
      },
    );
  }
}

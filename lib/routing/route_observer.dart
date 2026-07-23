import 'package:flutter/widgets.dart';

/// A global route observer so screens can react to being covered or revealed,
/// e.g. the YouTube player pausing when you open a channel on top of it.
final routeObserver = RouteObserver<ModalRoute<void>>();

/// Tracks whether the route most recently pushed on top was an imperative one
/// rather than a go_router page.
///
/// media_kit enters fullscreen with a raw `Navigator.push(PageRouteBuilder(...))`,
/// which covers the watch page and would otherwise trip the player's
/// pause-when-covered logic (freezing the video the instant you go fullscreen).
/// go_router navigations (tapping a channel, a related video) always carry a
/// [Page] in their settings; media_kit's fullscreen route does not. The player
/// consults this to pause only for the latter.
final navWatcher = _NavWatcher();

class _NavWatcher extends NavigatorObserver {
  bool lastPushWasImperative = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushWasImperative = route.settings is! Page;
  }
}

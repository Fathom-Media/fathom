import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the navigation rail is expanded (icons + labels) or collapsed
/// (icons only). Toggled from the rail's menu button.
class RailExtended extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final railExtendedProvider =
    NotifierProvider<RailExtended, bool>(RailExtended.new);

/// Whether the Libraries item in the sidebar is expanded to list the user's
/// libraries inline.
class LibrariesNavExpanded extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final librariesNavExpandedProvider =
    NotifierProvider<LibrariesNavExpanded, bool>(LibrariesNavExpanded.new);

/// Whether the Browse item in the sidebar is expanded to list Genres, Studios,
/// Artists, Playlists and Downloads inline.
class BrowseNavExpanded extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final browseNavExpandedProvider =
    NotifierProvider<BrowseNavExpanded, bool>(BrowseNavExpanded.new);

import 'package:flutter/material.dart';

/// The section-header label used inside settings and admin forms.
///
/// One definition so the whole app's grouping labels look identical. Previously
/// three styles coexisted (small-uppercase in preferences, large title-case in
/// admin, ad-hoc elsewhere), which read as three different apps. Small,
/// upper-cased, accent-coloured — the settings convention, applied everywhere.
///
/// Distinct from content-row headers (e.g. "Continue Watching"), which are large
/// title-case; this is only for form/settings groups.
class SettingsSectionHeader extends StatelessWidget {
  final String text;

  /// Trims the top gap when the header is the first thing in a list.
  final bool first;

  const SettingsSectionHeader(this.text, {super.key, this.first = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, first ? 8 : 22, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// The icon for a Jellyfin library/collection type.
///
/// One mapping so a library shows the same glyph everywhere. The sidebar and
/// the Libraries hub had drifted — a TV Shows library rendered as `tv_rounded`
/// in one and `live_tv_rounded` (the Live TV destination's own icon) in the
/// other. `tv_rounded` is kept for TV Shows so nothing collides with Live TV.
IconData collectionTypeIcon(String? type) => switch (type) {
      'movies' => Icons.movie_rounded,
      'tvshows' => Icons.tv_rounded,
      'music' => Icons.library_music_rounded,
      'musicvideos' => Icons.music_video_rounded,
      'books' => Icons.menu_book_rounded,
      'homevideos' || 'photos' => Icons.photo_library_rounded,
      'boxsets' => Icons.collections_bookmark_rounded,
      'livetv' => Icons.live_tv_rounded,
      'playlists' => Icons.playlist_play_rounded,
      _ => Icons.folder_rounded,
    };

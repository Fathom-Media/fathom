import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/youtube_download.dart';
import '../models/youtube_video.dart';
import '../state/youtube_providers.dart';
import 'add_to_youtube_playlist.dart';
import 'hover_pill_button.dart';
import 'youtube_download_sheet.dart';
import '../l10n/generated/app_localizations.dart';

/// One thing you can do to a video.
typedef YtAction = ({
  IconData icon,
  String label,
  bool tinted,
  VoidCallback onTap,
});

/// The actions a video has, defined once.
///
/// Both surfaces are built from [actionsFor]: the menu (overflow button and
/// right-click) and the watch page's action bar. They used to be two
/// hand-written lists, and they drifted immediately — Download was added to the
/// menu and silently missing from the watch page, which is the first place
/// anyone would look for it.
class YoutubeActions {
  YoutubeActions._();

  static String urlFor(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';

  static Future<void> copyLink(
      BuildContext context, YoutubeVideo video) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: urlFor(video.id)));
    messenger.showSnackBar(
        SnackBar(content: Text(l.ytLinkCopied)));
  }

  /// Opens the video on YouTube in the system browser.
  ///
  /// The point of this app is not needing the website, but there are things
  /// only it can do — commenting, or a video that refuses to play here — and
  /// dead-ending the viewer helps nobody.
  static Future<void> openInBrowser(
      BuildContext context, YoutubeVideo video) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(
      Uri.parse(urlFor(video.id)),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.ytCouldNotOpenBrowser)));
    }
  }

  /// Every action, in the order both surfaces show them.
  ///
  /// [onShowQueue] adds a Queue entry when something is queued and the caller
  /// can display it. The menu has nowhere to put a queue view, so it passes
  /// null and simply doesn't get that entry.
  static List<YtAction> actionsFor(
    BuildContext context,
    WidgetRef ref,
    YoutubeVideo video, {
    VoidCallback? onShowQueue,
  }) {
    final l = AppLocalizations.of(context);
    final queue = ref.watch(youtubeQueueProvider);
    final queued = queue.any((v) => v.id == video.id);

    // Colour is reserved for state: the row is uniform and neutral at rest, and
    // an action only takes the accent once its thing is active/done.
    final downloads = ref.watch(youtubeDownloadsProvider).asData?.value ??
        const <YoutubeDownload>[];
    final downloaded = downloads
        .any((d) => d.id == video.id && d.status == YtDownloadStatus.done);
    final downloading =
        downloads.any((d) => d.id == video.id && d.isActive);

    return [
      (
        icon: Icons.playlist_play_rounded,
        label: l.ytPlayNext,
        tinted: false,
        onTap: () => ref.read(youtubeQueueProvider.notifier).playNext(video),
      ),
      (
        icon: Icons.queue_rounded,
        label: queued ? l.ytQueued : l.ytAddToQueue,
        tinted: queued,
        onTap: () => ref.read(youtubeQueueProvider.notifier).add(video),
      ),
      if (onShowQueue != null && queue.isNotEmpty)
        (
          icon: Icons.queue_music_rounded,
          label: l.ytQueueCount(queue.length),
          tinted: true,
          onTap: onShowQueue,
        ),
      (
        icon: downloaded
            ? Icons.download_done_rounded
            : Icons.download_rounded,
        label: downloaded
            ? l.ytDownloaded
            : (downloading ? l.ytDownloading : l.ytDownload),
        tinted: downloaded || downloading,
        onTap: () => showYoutubeDownloadSheet(context, ref, video),
      ),
      (
        icon: Icons.link_rounded,
        label: l.ytCopyLink,
        tinted: false,
        onTap: () => copyLink(context, video),
      ),
      (
        icon: Icons.open_in_new_rounded,
        label: l.ytOpenInBrowser,
        tinted: false,
        onTap: () => openInBrowser(context, video),
      ),
    ];
  }

  /// The menu shown from a video's overflow button and from a right-click.
  ///
  /// [includePlaylist] swaps Add to Playlist for the caller's own Remove
  /// action, which is the useful verb once a video is already in one.
  static List<PopupMenuEntry<VoidCallback>> menuItems(
    BuildContext context,
    WidgetRef ref,
    YoutubeVideo video, {
    bool includePlaylist = true,
    List<PopupMenuEntry<VoidCallback>> extra = const [],
  }) {
    final l = AppLocalizations.of(context);
    final saved = ref
            .read(youtubeLocalPlaylistsProvider)
            .asData
            ?.value
            .any((p) => p.contains(video.id)) ??
        false;
    final actions = actionsFor(context, ref, video);

    PopupMenuItem<VoidCallback> item(YtAction a) => PopupMenuItem(
          value: a.onTap,
          child: _MenuRow(icon: a.icon, label: a.label, tint: a.tinted),
        );

    return [
      // Queue actions, then the playlist entry, then the rest below a divider.
      for (final a in actions.take(2)) item(a),
      if (includePlaylist)
        PopupMenuItem(
          value: () => showAddToYoutubePlaylist(context, video),
          child: _MenuRow(
            icon: saved
                ? Icons.playlist_add_check_rounded
                : Icons.playlist_add_rounded,
            label: saved ? l.ytSavedToPlaylist : l.ytAddToPlaylist,
            tint: saved,
          ),
        ),
      ...extra,
      const PopupMenuDivider(),
      for (final a in actions.skip(2)) item(a),
    ];
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool tint;
  const _MenuRow({required this.icon, required this.label, this.tint = false});

  @override
  Widget build(BuildContext context) {
    final color = tint ? Theme.of(context).colorScheme.primary : null;
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: color)),
    ]);
  }
}

/// The video's actions, as a bar under the channel row.
///
/// NewPipe keeps its uploader row and its control panel separate, and there's a
/// hard reason to copy that: crammed onto one line with the channel name and
/// Subscribe, these overflowed by 304px at a 420px width. A Wrap means it can
/// never overflow — the buttons drop to a second line instead.
class YoutubeVideoActionBar extends ConsumerWidget {
  final YoutubeVideo video;

  /// Shown before the rest, since it's the one with state worth seeing.
  final Widget? leading;

  /// Opens the queue. Without it, videos can be queued and never seen.
  final VoidCallback? onShowQueue;

  const YoutubeVideoActionBar({
    super.key,
    required this.video,
    this.leading,
    this.onShowQueue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ?leading,
        for (final a in YoutubeActions.actionsFor(context, ref, video,
            onShowQueue: onShowQueue))
          HoverPillButton(
            icon: a.icon,
            label: a.label,
            tinted: a.tinted,
            onTap: a.onTap,
          ),
      ],
    );
  }
}

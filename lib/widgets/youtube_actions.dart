import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/youtube_audio_item.dart';
import '../models/youtube_download.dart';
import '../models/youtube_video.dart';
import '../services/tv_mode.dart';
import '../state/audio_player.dart';
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
      // Start background audio straight from the row (no video screen). Up-next
      // then flows from the same shared queue as "Add to queue" below. Off TV.
      if (!isTvDevice)
        PopupMenuItem(
          value: () => ref
              .read(audioControllerProvider.notifier)
              .playYoutubeAudio(youtubeAudioItemOf(video)),
          child: _MenuRow(icon: Icons.headset_rounded, label: l.ytPlayAudio),
        ),
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

  /// The D-pad-friendly equivalent of the pop-up menu for TV: a bottom sheet of
  /// focusable rows built from the same [actionsFor]. On a TV the whole video
  /// card is one focus target (a remote can't reach a tiny inline 3-dot), so
  /// selecting a card opens this — Play first (autofocused), then the actions.
  static Future<void> showTvActionSheet(
    BuildContext context,
    WidgetRef ref,
    YoutubeVideo video, {
    bool includePlaylist = true,
    VoidCallback? onPlay,
  }) async {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final actions = actionsFor(context, ref, video);
    final saved = ref
            .read(youtubeLocalPlaylistsProvider)
            .asData
            ?.value
            .any((p) => p.contains(video.id)) ??
        false;

    ListTile row(IconData icon, String label, VoidCallback onTap,
            {bool autofocus = false, bool tint = false}) =>
        ListTile(
          autofocus: autofocus,
          leading: Icon(icon, color: tint ? scheme.primary : null),
          title: Text(label,
              style: tint ? TextStyle(color: scheme.primary) : null),
          onTap: () => Navigator.of(context).pop(onTap),
        );

    final chosen = await showModalBottomSheet<VoidCallback>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (onPlay != null)
              row(Icons.play_arrow_rounded, l.commonPlay, onPlay,
                  autofocus: true),
            for (final a in actions.take(2))
              row(a.icon, a.label, a.onTap, tint: a.tinted),
            if (includePlaylist)
              row(
                saved
                    ? Icons.playlist_add_check_rounded
                    : Icons.playlist_add_rounded,
                saved ? l.ytSavedToPlaylist : l.ytAddToPlaylist,
                () => showAddToYoutubePlaylist(context, video),
                tint: saved,
              ),
            const Divider(),
            for (final a in actions.skip(2))
              row(a.icon, a.label, a.onTap, tint: a.tinted),
          ],
        ),
      ),
    );
    chosen?.call();
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

  /// The player's live position, so "Listen" resumes the audio exactly where
  /// the video was (falls back to watch history when absent).
  final Duration Function()? currentPosition;

  const YoutubeVideoActionBar({
    super.key,
    required this.video,
    this.leading,
    this.onShowQueue,
    this.currentPosition,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ?leading,
        // "Listen": drop the video and keep the audio playing in the background,
        // through the same player/notification as music and radio. A phone/
        // desktop paradigm — a TV is always on-screen, so it's hidden there.
        if (!isTvDevice)
          HoverPillButton(
            icon: Icons.headset_rounded,
            label: l.ytListen,
            onTap: () => _listenInBackground(context, ref),
          ),
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

  void _listenInBackground(BuildContext context, WidgetRef ref) {
    final audio = ref.read(audioControllerProvider.notifier);
    // Resume exactly where the video is: the live player position if we have it,
    // else the (whole-second, async) watch-history entry.
    final live = currentPosition?.call();
    final entry = ref.read(youtubeHistoryProvider.notifier).entryFor(video.id);
    final startAt = (live != null && live > Duration.zero)
        ? live
        : (entry != null && !entry.finished)
            ? entry.position
            : Duration.zero;
    final item = YoutubeAudioItem(
      videoId: video.id,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnailUrl,
      duration: video.duration,
    );
    // Drop the video screen first (stops the video player so audio isn't
    // doubled), then start the background audio. Up-next carries over: it's the
    // same shared youtubeQueueProvider the video player was using.
    Navigator.of(context).maybePop();
    audio.playYoutubeAudio(item, startAt: startAt);
  }
}

/// Starts background YouTube audio from a video row (no video screen involved),
/// so up-next flows from the shared queue / autoplay. Shared helper for the
/// row menu entry.
YoutubeAudioItem youtubeAudioItemOf(YoutubeVideo v) => YoutubeAudioItem(
      videoId: v.id,
      title: v.title,
      author: v.author,
      thumbnailUrl: v.thumbnailUrl,
      duration: v.duration,
    );

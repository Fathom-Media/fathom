import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/youtube_local_playlist.dart';
import '../models/youtube_video.dart';
import '../state/youtube_providers.dart';
import 'hover_pill_button.dart';
import 'tv_keyboard.dart';
import '../l10n/generated/app_localizations.dart';

/// Pick a playlist to drop [video] into, or make one on the spot.
///
/// Ticks show what the video is already in, and tapping toggles it, so this
/// doubles as "take it back out" without a second menu somewhere else.
Future<void> showAddToYoutubePlaylist(
  BuildContext context,
  YoutubeVideo video,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddToPlaylistSheet(video: video),
    );

/// The playlist action for a video, showing whether it's already saved.
///
/// A static 'Add' icon gives no way to tell a saved video from an unsaved one
/// without opening the sheet, which is the only place the state was visible.
/// Saved shows a ticked icon in the accent colour; the sheet still handles both
/// directions, since a video can be in several playlists and 'remove' would
/// have to ask which.
class AddToPlaylistButton extends ConsumerWidget {
  final YoutubeVideo video;
  const AddToPlaylistButton({super.key, required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final saved = ref.watch(youtubeLocalPlaylistsProvider).asData?.value
            .any((p) => p.contains(video.id)) ??
        false;
    return HoverPillButton(
      icon: saved
          ? Icons.playlist_add_check_rounded
          : Icons.playlist_add_rounded,
      label: saved ? l.ytSavedToPlaylist : l.ytAddToPlaylist,
      tinted: saved,
      onTap: () => showAddToYoutubePlaylist(context, video),
    );
  }
}

class _AddToPlaylistSheet extends ConsumerWidget {
  final YoutubeVideo video;
  const _AddToPlaylistSheet({required this.video});

  Future<void> _newPlaylist(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ytNewPlaylist),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.ytName,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l.ytCreate),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final notifier = ref.read(youtubeLocalPlaylistsProvider.notifier);
    final playlist = await notifier.create(name);
    // Creating one from here means you wanted this video in it.
    await notifier.addVideo(playlist.id, video);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final playlists =
        ref.watch(youtubeLocalPlaylistsProvider).asData?.value ??
            const <YoutubeLocalPlaylist>[];

    return SafeArea(
      // Bounded, and the list scrolls inside it: a long list of playlists must
      // not push this past the top of the screen.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title stays constant, like YouTube's own sheet: the ticks say
            // where it's saved, so restating that up here just competes with
            // them.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
              child: Text(l.ytSaveToPlaylist,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            // Its own line, not tacked onto the title. Run together they read
            // as one grey blob and the instruction disappears into the title —
            // which is exactly how it was missed.
            if (playlists.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.ytTickToAdd,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(l.ytNewPlaylist),
              onTap: () async {
                await _newPlaylist(context, ref);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            if (playlists.isNotEmpty) const Divider(height: 1),
            Flexible(
              child: playlists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Text(
                        l.ytNoPlaylistsDevice,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (_, i) {
                        final p = playlists[i];
                        final has = p.contains(video.id);
                        return CheckboxListTile(
                          value: has,
                          title: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(has
                              ? l.ytPlaylistSavedSubtitle(p.countLabel(l))
                              : p.countLabel(l)),
                          onChanged: (_) {
                            final n = ref
                                .read(youtubeLocalPlaylistsProvider.notifier);
                            has
                                ? n.removeVideo(p.id, video.id)
                                : n.addVideo(p.id, video);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

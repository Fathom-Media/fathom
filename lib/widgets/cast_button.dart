import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/cast.dart';
import 'hover_pill_button.dart';

/// A cast icon that opens a Chromecast device picker and casts the media
/// resolved by [mediaUrl] (lazily, at tap time, so a live-updating stream URL is
/// current). Renders nothing where Cast is unavailable (non-Android, or no
/// Google Play Services), so it's safe to drop into any player chrome.
class CastButton extends ConsumerWidget {
  /// Resolves a single item's URL + content type (video). Null result surfaces
  /// an error. Ignored when [queueResolve] is set.
  final Future<({String url, String contentType})?> Function()? resolve;

  /// Resolves a whole queue to hand the receiver (music), with the index to
  /// start on. When set, this is used instead of [resolve] so Skip advances on
  /// the device. Items: {url, contentType, title, subtitle, image}.
  final Future<({List<Map<String, dynamic>> items, int startIndex})?>
      Function()? queueResolve;
  final String? title;
  final String? subtitle;
  final String? image;
  final int Function()? position;
  final Color? color;

  /// Called once a cast has been kicked off (device picked + media/queue sent).
  /// The detail page uses it to open the player so its cast remote is shown.
  final VoidCallback? onStarted;

  /// Video casting shows only video-capable receivers (a speaker can't render
  /// video, and Cast can't extract a video's audio track). Music sets this
  /// false so audio-only speakers are offered too.
  final bool videoOnly;

  /// Renders as a [HoverPillButton] (an icon that expands to its label on
  /// hover/press/focus) so it matches the Play/Download pills beside it on the
  /// detail page, instead of the plain icon used in player chrome.
  final bool pill;

  const CastButton({
    super.key,
    this.resolve,
    this.queueResolve,
    this.title,
    this.subtitle,
    this.image,
    this.position,
    this.color,
    this.onStarted,
    this.videoOnly = true,
    this.pill = false,
  }) : assert(resolve != null || queueResolve != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castControllerProvider);
    // Hide unless the Cast SDK is present AND a Cast device is actually reachable
    // (like any major app: no button off Wi-Fi / with no Chromecast on the LAN).
    // Stay visible while connected so the session can be ended.
    if (!cast.available || (!cast.routeAvailable && !cast.connected)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final icon = cast.connected
        ? Icons.cast_connected_rounded
        : Icons.cast_rounded;
    if (pill) {
      return HoverPillButton(
        icon: icon,
        label: l.castTo,
        color: color,
        onTap: () => _open(context, ref),
      );
    }
    return IconButton(
      tooltip: l.castTo,
      color: color,
      icon: Icon(icon),
      onPressed: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(castControllerProvider.notifier);
    await ctrl.startDiscovery();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final l = AppLocalizations.of(ctx);
          final cast = ref.watch(castControllerProvider);
          final devices = videoOnly
              ? cast.devices.where((d) => d.videoCapable).toList()
              : cast.devices;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(l.castTo,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700)),
                ),
                if (devices.isEmpty && !cast.connected)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5)),
                        const SizedBox(width: 14),
                        Text(l.castSearching),
                      ],
                    ),
                  ),
                // Each device appears once. The connected one shows its state
                // inline with a Disconnect action instead of a second row.
                for (final d in devices)
                  () {
                    final isConnected =
                        cast.connected && cast.deviceName == d.name;
                    return ListTile(
                      leading: Icon(isConnected
                          ? Icons.cast_connected_rounded
                          : (d.videoCapable
                              ? Icons.cast_rounded
                              : Icons.speaker_rounded)),
                      title: Text(d.name),
                      trailing: isConnected
                          ? TextButton(
                              onPressed: () {
                                ctrl.endSession();
                                Navigator.pop(ctx);
                              },
                              child: Text(l.castDisconnect),
                            )
                          : null,
                      onTap: isConnected
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(ctx);
                              Navigator.pop(ctx);
                              // Resolve what to send BEFORE selecting the device,
                              // so a failure doesn't start a dead session.
                              if (queueResolve != null) {
                                final q = await queueResolve!();
                                if (q == null) {
                                  messenger.showSnackBar(
                                      SnackBar(content: Text(l.castFailed)));
                                  return;
                                }
                                await ctrl.selectDevice(d.id, name: d.name);
                                await ctrl.loadQueue(
                                    items: q.items,
                                    startIndex: q.startIndex,
                                    position: position?.call() ?? 0);
                                onStarted?.call();
                                return;
                              }
                              final media = await resolve!();
                              if (media == null) {
                                messenger.showSnackBar(
                                    SnackBar(content: Text(l.castFailed)));
                                return;
                              }
                              await ctrl.selectDevice(d.id, name: d.name);
                              // Native queues this until the session connects.
                              await ctrl.loadMedia(
                                url: media.url,
                                title: title,
                                subtitle: subtitle,
                                image: image,
                                contentType: media.contentType,
                                position: position?.call() ?? 0,
                              );
                              onStarted?.call();
                            },
                    );
                  }(),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
    await ctrl.stopDiscovery();
  }
}

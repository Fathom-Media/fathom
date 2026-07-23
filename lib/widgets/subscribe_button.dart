import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/youtube_channel.dart';
import '../state/youtube_providers.dart';
import 'hover_pill_button.dart';
import '../l10n/generated/app_localizations.dart';

/// Subscribe / Subscribed toggle for a channel. An icon-only pill that expands
/// on hover, matching the video action bar: accent-filled to subscribe, a soft
/// accent wash with a check once subscribed.
class SubscribeButton extends ConsumerWidget {
  final YoutubeChannel channel;
  const SubscribeButton({super.key, required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final subs = ref.watch(youtubeSubscriptionsProvider).asData?.value ??
        const <YoutubeChannel>[];
    final subscribed = subs.any((c) => c.id == channel.id);

    return HoverPillButton(
      icon: subscribed ? Icons.check_rounded : Icons.add_rounded,
      label: subscribed ? l.ytSubscribed : l.ytSubscribe,
      tinted: subscribed,
      primary: !subscribed,
      onTap: () =>
          ref.read(youtubeSubscriptionsProvider.notifier).toggle(channel),
    );
  }
}

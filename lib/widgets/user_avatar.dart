import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';

/// Circular avatar for an arbitrary Jellyfin user (by id + image tag). Shows
/// their profile image when set, otherwise the first letter of their name.
class JellyfinAvatar extends ConsumerWidget {
  final String userId;
  final String? tag;
  final String name;
  final double radius;
  const JellyfinAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.tag,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    final scheme = Theme.of(context).colorScheme;

    final letter = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final url = (session != null && tag != null)
        ? client.userImageUrl(
            baseUrl: session.baseUrl,
            userId: userId,
            tag: tag,
            size: (radius * 4).round(),
          )
        : null;

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url, headers: headers),
      child: url == null
          ? Text(letter,
              style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: radius * 0.9))
          : null,
    );
  }
}

/// Circular avatar for the signed-in Jellyfin user. Shows their profile image
/// when set, otherwise the first letter of their name on a tinted circle.
class UserAvatar extends ConsumerWidget {
  final double radius;
  const UserAvatar({super.key, this.radius = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final user = ref.watch(currentUserProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    final scheme = Theme.of(context).colorScheme;

    final name = user?.name ?? session?.userName ?? '?';
    final letter = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    final url = (session != null && user?.primaryImageTag != null)
        ? client.userImageUrl(
            baseUrl: session.baseUrl,
            userId: user!.id,
            tag: user.primaryImageTag,
            size: (radius * 4).round(),
          )
        : null;

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url, headers: headers),
      child: url == null
          ? Text(letter,
              style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: radius * 0.9))
          : null,
    );
  }
}

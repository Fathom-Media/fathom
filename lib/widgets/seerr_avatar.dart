import 'package:flutter/material.dart';

/// A user avatar, matching Jellyseerr: the user's picture when there is one,
/// otherwise their initial on the accent colour.
class SeerrAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;
  const SeerrAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? NetworkImage(avatarUrl!)
          : null,
      // Shown while the image loads and if it fails.
      child: Text(
        initial,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

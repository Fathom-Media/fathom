import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/user_avatar.dart';

/// The signed-in user's profile: large avatar with change / remove actions.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  Future<void> _changePhoto() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final user = ref.read(currentUserProvider).asData?.value;
    if (session == null || user == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file =
        (result != null && result.files.isNotEmpty) ? result.files.first : null;
    final bytes = file?.bytes;
    if (bytes == null) return;

    final ext = (file!.extension ?? 'jpg').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() => _busy = true);
    try {
      await ref.read(jellyfinClientProvider).uploadUserImage(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            userId: user.id,
            bytes: bytes,
            contentType: mime,
          );
      ref.invalidate(currentUserProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(l.profilePictureUpdated)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final user = ref.read(currentUserProvider).asData?.value;
    if (session == null || user == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(jellyfinClientProvider).deleteUserImage(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            userId: user.id,
          );
      ref.invalidate(currentUserProvider);
      messenger
          .showSnackBar(SnackBar(content: Text(l.profilePictureRemoved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final user = ref.watch(currentUserProvider).asData?.value;
    final hasPhoto = user?.primaryImageTag != null;

    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.profileTitle)),
      body: Stack(
        children: [
          // Ambient accent band behind the avatar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.5), width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 2),
                    ],
                  ),
                  child: const UserAvatar(radius: 64),
                ),
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : _changePhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.photo_camera_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(user?.name ?? session?.userName ?? '—',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(session?.serverName ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            if (_busy)
              const CircularProgressIndicator()
            else ...[
              FilledButton.icon(
                onPressed: _changePhoto,
                icon: const Icon(Icons.upload_rounded),
                label: Text(l.profileChangePhoto),
              ),
              if (hasPhoto)
                TextButton.icon(
                  onPressed: _removePhoto,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  label: Text(l.profileRemovePhoto,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ],
        ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/item_grid.dart';
import '../widgets/media_image.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';

/// Browse music artists; tap one to see their albums.
class ArtistsScreen extends ConsumerWidget {
  const ArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(artistsProvider);
    return Scaffold(
      appBar: AppBar(leading: mobileLeading(context), title: Text(l.browseArtists)),
      body: async.when(
        loading: () => const PosterGridSkeleton(
            maxExtent: 150, aspectRatio: 0.8, circular: true),
        error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(artistsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
                icon: Icons.person_rounded, title: l.browseNoArtists);
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 18,
              crossAxisSpacing: 14,
              childAspectRatio: 0.8,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => EntranceFade(
              index: i,
              onceKey: list[i].id,
              child: _ArtistTile(artist: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final BaseItemDto artist;
  const _ArtistTile({required this.artist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverLift(
      child: InkWell(
        onTap: () => context.push('/artist', extra: artist),
        borderRadius: BorderRadius.circular(80),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipOval(
                  child: MediaImage(item: artist, placeholderIcon: Icons.person_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(artist.name,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A single artist's albums.
class ArtistAlbumsScreen extends ConsumerWidget {
  final String artistId;
  final String artistName;
  const ArtistAlbumsScreen(
      {super.key, required this.artistId, required this.artistName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(artistAlbumsProvider(artistId));
    return Scaffold(
      appBar: AppBar(title: Text(artistName)),
      body: ItemGridBody(
        items: async,
        emptyTitle: l.browseNoAlbums,
        emptyIcon: Icons.album_rounded,
      ),
    );
  }
}

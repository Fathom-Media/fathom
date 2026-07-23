import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/base_item.dart';
import 'library_providers.dart';
import 'providers.dart';
import 'session_controller.dart';

/// Extracts a signature accent color from an item's artwork (backdrop, else
/// poster). Powers the ambient, art-driven tinting on detail/now-playing.
/// Returns null when there's no image or extraction fails.
final itemAccentProvider =
    FutureProvider.autoDispose.family<Color?, BaseItemDto>((ref, item) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return null;
  final client = ref.watch(jellyfinClientProvider);
  final headers = ref.watch(imageHeadersProvider);

  final ({String id, String type, String tag})? pick;
  if (item.backdropImageTags.isNotEmpty) {
    pick = (id: item.id, type: 'Backdrop', tag: item.backdropImageTags.first);
  } else if (item.primaryImageTag != null) {
    pick = (id: item.id, type: 'Primary', tag: item.primaryImageTag!);
  } else if (item.albumId != null && item.albumPrimaryImageTag != null) {
    pick = (id: item.albumId!, type: 'Primary', tag: item.albumPrimaryImageTag!);
  } else {
    pick = null;
  }
  if (pick == null) return null;

  final url = client.imageUrl(
    baseUrl: session.baseUrl,
    itemId: pick.id,
    type: pick.type,
    tag: pick.tag,
    maxWidth: 320,
  );

  try {
    final palette = await PaletteGenerator.fromImageProvider(
      NetworkImage(url, headers: headers),
      size: const Size(220, 140),
      maximumColorCount: 8,
    );
    return palette.vibrantColor?.color ??
        palette.dominantColor?.color ??
        palette.mutedColor?.color;
  } catch (_) {
    return null;
  }
});

import 'package:flutter/material.dart';

import '../api/jellyfin_client.dart';
import '../models/base_item.dart';

/// A single scrub-preview thumbnail cropped out of a Jellyfin trickplay sprite
/// sheet, with a time label beneath it. Shared by the media_kit player chrome
/// and the native ExoPlayer seek bar so both draw the identical bubble.
///
/// The crop is done by rendering the whole sheet oversized inside a clipping
/// [SizedBox] and translating it so the wanted cell sits at the top-left.
class TrickplayThumb extends StatelessWidget {
  final JellyfinClient client;
  final String baseUrl;
  final String itemId;
  final TrickplayInfo info;
  final int resolutionWidth;
  final Map<String, String> headers;
  final int positionMs;
  final double thumbWidth;
  final double thumbHeight;
  final String label;

  const TrickplayThumb({
    super.key,
    required this.client,
    required this.baseUrl,
    required this.itemId,
    required this.info,
    required this.resolutionWidth,
    required this.headers,
    required this.positionMs,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final maxN = info.thumbnailCount > 0 ? info.thumbnailCount - 1 : 0;
    final n = (positionMs ~/ (info.interval > 0 ? info.interval : 10000))
        .clamp(0, maxN);
    final perTile = info.perTile > 0 ? info.perTile : 1;
    final tileIndex = n ~/ perTile;
    final within = n % perTile;
    final row = within ~/ info.tileWidth;
    final col = within % info.tileWidth;

    final dispH = thumbHeight;
    final dispW = thumbWidth;
    final url = client.trickplayTileUrl(
      baseUrl: baseUrl,
      itemId: itemId,
      width: resolutionWidth,
      tileIndex: tileIndex,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: dispW,
            height: dispH,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(-col * dispW, -row * dispH),
                child: Image.network(
                  url,
                  width: dispW * info.tileWidth,
                  height: dispH * info.tileHeight,
                  fit: BoxFit.fill,
                  headers: headers,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Formats a duration as `m:ss` or `h:mm:ss`, keeping a leading minus for a
/// negative (time-remaining) value.
String fmtTime(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  final s = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  return neg ? '-$s' : s;
}

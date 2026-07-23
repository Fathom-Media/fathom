import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The on-disk cache for network images (posters, backdrops, thumbnails).
///
/// Freshness by source:
/// - Jellyfin URLs carry an image tag and TMDB/Seerr URLs are content-hashed,
///   so a replaced image is a new URL and refreshes on its own, immediately.
/// - YouTube thumbnail URLs are stable, so those refresh when an entry passes
///   [stalePeriod] and the manager revalidates it.
///
/// The object cap is far above flutter_cache_manager's default of 200 so a wall
/// of posters actually persists across launches instead of being evicted and
/// re-downloaded.
final fathomImageCache = CacheManager(
  Config(
    'fathomImageCache',
    stalePeriod: const Duration(days: 21),
    maxNrOfCacheObjects: 2000,
  ),
);

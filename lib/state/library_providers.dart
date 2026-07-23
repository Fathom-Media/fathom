import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../models/guide_data.dart';
import '../models/user_dto.dart';
import 'providers.dart';
import 'session_controller.dart';

/// Whether the active server is reachable, re-probed every 30s so the app
/// notices going offline mid-session (not just at load). Emits true when no
/// session is active (nothing to be offline from).
final serverReachableProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) {
    yield true;
    return;
  }
  final client = ref.watch(jellyfinClientProvider);
  while (true) {
    yield await client.pingServer(session.baseUrl);
    await Future<void>.delayed(const Duration(seconds: 30));
  }
});

/// The signed-in user's live policy (admin / delete rights), fetched fresh so
/// it works even for sessions saved before we captured the flag.
final currentUserProvider = FutureProvider.autoDispose<UserDto?>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return null;
  final client = ref.watch(jellyfinClientProvider);
  try {
    return await client.getCurrentUser(
        baseUrl: session.baseUrl, token: session.accessToken);
  } catch (_) {
    return null;
  }
});

/// Auth headers to attach when loading images with `Image.network`.
final imageHeadersProvider = Provider<Map<String, String>>((ref) {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  final client = ref.watch(jellyfinClientProvider);
  if (session == null) return const {};
  return {'Authorization': client.authHeader(token: session.accessToken)};
});

final userViewsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getUserViews(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

final resumeItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getResumeItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// Full details for a cast/crew member (biography, images).
final personDetailProvider = FutureProvider.autoDispose
    .family<BaseItemDto?, String>((ref, id) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null || id.isEmpty) return null;
  try {
    return await ref.watch(jellyfinClientProvider).getItem(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: id,
        );
  } catch (_) {
    return null;
  }
});

/// "More Like This" — titles similar to a given item.
final similarItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, itemId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  return ref.watch(jellyfinClientProvider).getSimilar(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: itemId,
      );
});

/// Recently added items within a single library (for per-library Home rows).
final latestInLibraryProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, parentId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getLatestItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    parentId: parentId,
    limit: 16,
  );
});

/// The user's global Next Up queue (next episodes across all series).
final nextUpItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getNextUpItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// Items for the Home hero, the way Fladder/Moonfin do it: what you're
/// watching first (Continue Watching, then Next Up), filled with Recently
/// Added when you're all caught up. De-duplicated, capped at 8.
final heroItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final results = await Future.wait([
    ref.watch(resumeItemsProvider.future),
    ref.watch(nextUpItemsProvider.future),
    ref.watch(latestItemsProvider.future),
  ]);
  final seen = <String>{};
  final out = <BaseItemDto>[];
  for (final list in results) {
    for (final item in list) {
      if (seen.add(item.id)) out.add(item);
      if (out.length >= 8) break;
    }
    if (out.length >= 8) break;
  }
  return out;
});

final latestItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getLatestItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// Live TV channels with their current program.
final liveTvChannelsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getLiveTvChannels(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// All genres across the user's libraries.
final genresProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getGenres(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// All studios/networks across the user's libraries.
final studiosProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getStudios(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// Movies + series from a given studio/network, newest first.
typedef StudioQuery = ({String studio, String sortBy, String sortOrder});

final studioItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, StudioQuery>((ref, q) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    studios: q.studio,
    includeItemTypes: 'Movie,Series',
    recursive: true,
    sortBy: q.sortBy,
    sortOrder: q.sortOrder,
    limit: 300,
  );
  return res.items;
});

/// All music artists.
final artistsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getArtists(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// A given artist's albums, newest first.
final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, artistId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    albumArtistIds: artistId,
    includeItemTypes: 'MusicAlbum',
    recursive: true,
    sortBy: 'PremiereDate,SortName',
    sortOrder: 'Descending',
    limit: 300,
  );
  return res.items;
});

typedef GenreQuery = ({String genre, String sortBy, String sortOrder});

/// Movies + series tagged with a given genre, in the requested sort order.
final genreItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, GenreQuery>((ref, q) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    genres: q.genre,
    includeItemTypes: 'Movie,Series',
    recursive: true,
    sortBy: q.sortBy,
    sortOrder: q.sortOrder,
    limit: 300,
  );
  return res.items;
});

/// A person's filmography (movies + series they appear in), newest first.
final personItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, personId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    personIds: personId,
    includeItemTypes: 'Movie,Series',
    recursive: true,
    sortBy: 'PremiereDate,ProductionYear',
    sortOrder: 'Descending',
    limit: 200,
  );
  return res.items;
});

/// The user's favorites (movies, series, albums).
final favoriteItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    isFavorite: true,
    includeItemTypes: 'Movie,Series,MusicAlbum',
    recursive: true,
    sortBy: 'SortName',
    limit: 300,
  );
  return res.items;
});

/// Children of a collection (BoxSet).
final collectionItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, boxSetId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    parentId: boxSetId,
    sortBy: 'SortName',
    limit: 300,
  );
  return res.items;
});

/// DVR recordings.
final recordingsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getRecordings(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// EPG guide: channels + their programs. The window starts short (so it loads
/// fast) and grows in chunks via [GuideController.loadMore] as the user scrolls
/// right, until the server has no more EPG data.
class GuideController extends AsyncNotifier<GuideData> {
  // Initial span, then how much each scroll-triggered fetch adds. Kept modest so
  // the first paint is quick and later chunks stay light.
  static const _initialHours = 12;
  static const _chunkHours = 12;
  // A hard ceiling so a provider with unbounded EPG can't grow the grid forever.
  static const _maxHours = 14 * 24;

  @override
  Future<GuideData> build() async {
    final channels = await ref.watch(liveTvChannelsProvider.future);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    // Window: floor to the previous half hour so tiles align to the ruler.
    final now = DateTime.now();
    final start = DateTime(
        now.year, now.month, now.day, now.hour, now.minute >= 30 ? 30 : 0);
    final end = start.add(const Duration(hours: _initialHours));
    if (channels.isEmpty || session == null) {
      return GuideData(
        channels: channels,
        programsByChannel: const {},
        windowStart: start,
        windowEnd: end,
        atEnd: true,
      );
    }
    final byChannel = await _fetch(session, channels, start, end);
    return GuideData(
      channels: channels,
      programsByChannel: byChannel,
      windowStart: start,
      windowEnd: end,
    );
  }

  /// Extend the window by another chunk, fetching only the new segment and
  /// merging it in. No-op while a fetch is in flight, once the end of the EPG is
  /// reached, or at the safety ceiling.
  Future<void> loadMore() async {
    final data = state.asData?.value;
    if (data == null || data.loadingMore || data.atEnd) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || data.channels.isEmpty) return;

    final segStart = data.windowEnd;
    final segEnd = segStart.add(const Duration(hours: _chunkHours));
    state = AsyncData(data.copyWith(loadingMore: true));
    try {
      final seg = await _fetch(session, data.channels, segStart, segEnd);
      final added = seg.values.fold<int>(0, (n, l) => n + l.length);
      // No programs in the new segment means the provider's EPG stops here.
      final reachedCeiling =
          segEnd.difference(data.windowStart).inHours >= _maxHours;
      final merged = <String, List<BaseItemDto>>{
        for (final e in data.programsByChannel.entries) e.key: List.of(e.value),
      };
      for (final e in seg.entries) {
        (merged[e.key] ??= <BaseItemDto>[]).addAll(e.value);
      }
      state = AsyncData(data.copyWith(
        programsByChannel: merged,
        windowEnd: segEnd,
        loadingMore: false,
        atEnd: added == 0 || reachedCeiling,
      ));
    } catch (_) {
      // A failed chunk shouldn't wipe the grid; just stop extending.
      state = AsyncData(data.copyWith(loadingMore: false, atEnd: true));
    }
  }

  Future<Map<String, List<BaseItemDto>>> _fetch(dynamic session,
      List<BaseItemDto> channels, DateTime start, DateTime end) async {
    final client = ref.read(jellyfinClientProvider);
    final programs = await client.getGuidePrograms(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      channelIds: channels.map((c) => c.id).toList(),
      start: start,
      end: end,
    );
    final byChannel = <String, List<BaseItemDto>>{};
    for (final p in programs) {
      (byChannel[p.channelId ?? ''] ??= []).add(p);
    }
    return byChannel;
  }
}

final guideProvider =
    AsyncNotifierProvider.autoDispose<GuideController, GuideData>(
        GuideController.new);

/// Full detail for a single item, by id.
final itemDetailProvider =
    FutureProvider.autoDispose.family<BaseItemDto, String>((ref, itemId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) throw StateError('Not signed in');
  final client = ref.watch(jellyfinClientProvider);
  return client.getItem(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    itemId: itemId,
  );
});

/// Tracks of a music album, in disc/track order.
final albumTracksProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, albumId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    parentId: albumId,
    includeItemTypes: 'Audio',
    sortBy: 'ParentIndexNumber,IndexNumber',
    limit: 500,
  );
  return res.items;
});

/// The next episode to watch for a series (null if none).
final nextUpProvider =
    FutureProvider.autoDispose.family<BaseItemDto?, String>((ref, seriesId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return null;
  final client = ref.watch(jellyfinClientProvider);
  return client.getNextUp(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    seriesId: seriesId,
  );
});

/// All episodes of a series, in order.
final episodesProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, seriesId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getEpisodes(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    seriesId: seriesId,
  );
});

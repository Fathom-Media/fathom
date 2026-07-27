import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import '../models/authentication_result.dart';
import '../models/base_item.dart';
import '../models/items_result.dart';
import '../models/media_segment.dart';
import '../models/public_system_info.dart';
import '../models/user_dto.dart';
import '../models/lyrics.dart';

/// A user-facing error carrying a message safe to show in the UI.
class JellyfinException implements Exception {
  final String message;
  JellyfinException(this.message);
  @override
  String toString() => message;
}

/// An opened live stream: the playable URL plus the ids needed to close it and
/// release the tuner.
class LiveStreamHandle {
  final String url;
  final String? liveStreamId;
  final String? playSessionId;
  const LiveStreamHandle({
    required this.url,
    this.liveStreamId,
    this.playSessionId,
  });
}

/// Thin, typed Jellyfin API client. Grows per phase; for now it covers the
/// connect + login surface. All auth uses the MediaBrowser Authorization
/// header scheme that Jellyfin expects.
class JellyfinClient {
  final String deviceId;
  final String clientName;
  final String clientVersion;
  final Dio _dio;

  /// [httpClient] is for tests, which swap in an adapter to inspect what
  /// actually goes over the wire. Production leaves it null.
  JellyfinClient({
    required this.deviceId,
    this.clientName = 'Fathom',
    this.clientVersion = '0.1.0',
    Dio? httpClient,
  }) : _dio = httpClient ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ));

  /// Builds the `Authorization` header. Include [token] once authenticated.
  String authHeader({String? token}) {
    final parts = <String>[
      'MediaBrowser Client="$clientName"',
      'Device="Linux"',
      'DeviceId="$deviceId"',
      'Version="$clientVersion"',
    ];
    if (token != null) parts.add('Token="$token"');
    return parts.join(', ');
  }

  /// Normalizes user-entered addresses: adds https:// if no scheme is given,
  /// trims whitespace and trailing slashes.
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) {
      throw JellyfinException('Please enter a server address.');
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  /// A quick yes/no on whether the server answers, for the offline check. Uses
  /// the unauthenticated /System/Info/Public with a short timeout: a reachable
  /// server replies in milliseconds, so a slow failure means offline. Never
  /// throws, offline is an answer.
  Future<bool> pingServer(String baseUrl,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final probe = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
    ));
    try {
      final res = await probe.get('$baseUrl/System/Info/Public');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      probe.close();
    }
  }


  /// Validates that [baseUrl] points at a reachable Jellyfin server.
  Future<PublicSystemInfo> getPublicSystemInfo(String baseUrl) async {
    try {
      final res = await _dio.get('$baseUrl/System/Info/Public');
      final data = res.data;
      if (data is! Map) {
        throw JellyfinException(
            'That address did not return a Jellyfin server response.');
      }
      return PublicSystemInfo.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e, connecting: true));
    }
  }

  /// Authenticates with username + password.
  Future<AuthenticationResult> authenticateByName({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(headers: {
          'Authorization': authHeader(),
          'Content-Type': 'application/json',
        }),
      );
      return AuthenticationResult.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw JellyfinException('Incorrect username or password.');
      }
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Whether the server has Quick Connect turned on.
  Future<bool> quickConnectEnabled(String baseUrl) async {
    try {
      final res = await _dio.get('$baseUrl/QuickConnect/Enabled');
      return res.data == true || res.data == 'true';
    } on DioException {
      return false;
    }
  }

  /// Starts a Quick Connect request; returns the code to show the user and the
  /// secret to poll with.
  Future<({String secret, String code})> quickConnectInitiate(
      String baseUrl) async {
    try {
      final res = await _dio.get(
        '$baseUrl/QuickConnect/Initiate',
        options: Options(headers: {'Authorization': authHeader()}),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return (
        secret: data['Secret'] as String,
        code: data['Code'] as String,
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Polls a pending Quick Connect request; true once the user has approved it
  /// on an already-signed-in device.
  Future<bool> quickConnectPoll(String baseUrl, String secret) async {
    try {
      final res = await _dio.get(
        '$baseUrl/QuickConnect/Connect',
        queryParameters: {'secret': secret},
        options: Options(headers: {'Authorization': authHeader()}),
      );
      final data = res.data;
      return data is Map && data['Authenticated'] == true;
    } on DioException catch (e) {
      // 404 means the request expired or was cancelled server-side.
      if (e.response?.statusCode == 404) {
        throw JellyfinException('This Quick Connect request expired.');
      }
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Approves a Quick Connect code entered on another device (as the signed-in
  /// user). Returns true if the code was accepted.
  Future<bool> authorizeQuickConnect({
    required String baseUrl,
    required String token,
    required String code,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/QuickConnect/Authorize',
        queryParameters: {'code': code},
        options: _authed(token),
      );
      return res.data == true || res.data == 'true';
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw JellyfinException('That code was not found or has expired.');
      }
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Exchanges an approved Quick Connect secret for an access token.
  Future<AuthenticationResult> authenticateWithQuickConnect({
    required String baseUrl,
    required String secret,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Users/AuthenticateWithQuickConnect',
        data: {'Secret': secret},
        options: Options(headers: {
          'Authorization': authHeader(),
          'Content-Type': 'application/json',
        }),
      );
      return AuthenticationResult.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Options _authed(String token) =>
      Options(headers: {'Authorization': authHeader(token: token)});

  /// The user's libraries (Movies, TV Shows, Music, Live TV, ...).
  Future<List<BaseItemDto>> getUserViews({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    return _getItems('$baseUrl/Users/$userId/Views', token);
  }

  /// "Continue Watching" — partially played video items.
  Future<List<BaseItemDto>> getResumeItems({
    required String baseUrl,
    required String userId,
    required String token,
    int limit = 20,
  }) async {
    return _getItems(
      '$baseUrl/Users/$userId/Items/Resume',
      token,
      query: {
        'Limit': '$limit',
        'MediaTypes': 'Video',
        'Fields': 'PrimaryImageAspectRatio,Overview',
        'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
      },
    );
  }

  /// The user's global Next Up queue (next episodes across all series).
  Future<List<BaseItemDto>> getNextUpItems({
    required String baseUrl,
    required String userId,
    required String token,
    int limit = 20,
  }) {
    return _getItems(
      '$baseUrl/Shows/NextUp',
      token,
      query: {
        'UserId': userId,
        'Limit': '$limit',
        'Fields': 'PrimaryImageAspectRatio,Overview',
        'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
      },
    );
  }

  /// "Recently Added" — newest items, optionally scoped to one library.
  Future<List<BaseItemDto>> getLatestItems({
    required String baseUrl,
    required String userId,
    required String token,
    String? parentId,
    int limit = 20,
  }) async {
    return _getItems(
      '$baseUrl/Users/$userId/Items/Latest',
      token,
      query: {
        'Limit': '$limit',
        'Fields': 'Overview,PrimaryImageAspectRatio',
        'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
        'ParentId': ?parentId,
      },
    );
  }

  Future<List<BaseItemDto>> _getItems(
    String url,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res =
          await _dio.get(url, queryParameters: query, options: _authed(token));
      final data = res.data;
      final rawList = data is List
          ? data
          : (data is Map ? (data['Items'] as List? ?? const []) : const []);
      return rawList
          .whereType<Map>()
          .map((e) => BaseItemDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// General item query used for library browsing and search. Returns a page
  /// of items plus the total count so callers can page with [startIndex].
  Future<ItemsResult> getItems({
    required String baseUrl,
    required String userId,
    required String token,
    String? parentId,
    String? searchTerm,
    String? includeItemTypes,
    String? genres,
    String? studios,
    String? albumArtistIds,
    String? personIds,
    String? filters,
    bool? isFavorite,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    bool recursive = false,
    int startIndex = 0,
    int limit = 100,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Users/$userId/Items',
        queryParameters: {
          'ParentId': ?parentId,
          'SearchTerm': ?searchTerm,
          'IncludeItemTypes': ?includeItemTypes,
          'Genres': ?genres,
          'Studios': ?studios,
          'AlbumArtistIds': ?albumArtistIds,
          'PersonIds': ?personIds,
          'Filters': ?filters,
          'IsFavorite': isFavorite == null ? null : '$isFavorite',
          'SortBy': sortBy,
          'SortOrder': sortOrder,
          'Recursive': '$recursive',
          'StartIndex': '$startIndex',
          'Limit': '$limit',
          'Fields': 'PrimaryImageAspectRatio,ProductionYear',
          'ImageTypeLimit': '1',
          'EnableImageTypes': 'Primary,Backdrop,Thumb',
        },
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final items = (data['Items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BaseItemDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return ItemsResult(
        items: items,
        totalRecordCount:
            (data['TotalRecordCount'] as num?)?.toInt() ?? items.length,
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// All genres present in the user's libraries.
  Future<List<BaseItemDto>> getGenres({
    required String baseUrl,
    required String userId,
    required String token,
    String? parentId,
  }) {
    return _getItems(
      '$baseUrl/Genres',
      token,
      query: {
        'UserId': userId,
        'ParentId': ?parentId,
        'SortBy': 'SortName',
        'Recursive': 'true',
      },
    );
  }

  /// The user's playlists.
  Future<List<BaseItemDto>> getPlaylists({
    required String baseUrl,
    required String userId,
    required String token,
  }) {
    return _getItems(
      '$baseUrl/Users/$userId/Items',
      token,
      query: {
        'IncludeItemTypes': 'Playlist',
        'Recursive': 'true',
        'SortBy': 'SortName',
        'Fields': 'ChildCount,PrimaryImageAspectRatio',
      },
    );
  }

  /// The items inside a playlist, in playlist order. Each carries a
  /// `PlaylistItemId` used to remove it.
  Future<List<BaseItemDto>> getPlaylistItems({
    required String baseUrl,
    required String userId,
    required String token,
    required String playlistId,
  }) {
    return _getItems(
      '$baseUrl/Playlists/$playlistId/Items',
      token,
      query: {
        'UserId': userId,
        'Fields': 'PrimaryImageAspectRatio,ProductionYear',
      },
    );
  }

  /// Create a playlist, optionally seeded with items. Returns the new id.
  Future<String> createPlaylist({
    required String baseUrl,
    required String userId,
    required String token,
    required String name,
    List<String> itemIds = const [],
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Playlists',
        data: {
          'Name': name,
          'UserId': userId,
          if (itemIds.isNotEmpty) 'Ids': itemIds,
        },
        options: _authed(token),
      );
      return (res.data as Map?)?['Id'] as String? ?? '';
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> addToPlaylist({
    required String baseUrl,
    required String userId,
    required String token,
    required String playlistId,
    required List<String> itemIds,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Playlists/$playlistId/Items',
        queryParameters: {'Ids': itemIds.join(','), 'UserId': userId},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Remove entries from a playlist. [entryIds] are the per-entry
  /// `PlaylistItemId`s, not the underlying item ids.
  Future<void> removeFromPlaylist({
    required String baseUrl,
    required String token,
    required String playlistId,
    required List<String> entryIds,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/Playlists/$playlistId/Items',
        queryParameters: {'EntryIds': entryIds.join(',')},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> deletePlaylist({
    required String baseUrl,
    required String token,
    required String playlistId,
  }) =>
      deleteItem(baseUrl: baseUrl, token: token, itemId: playlistId);

  /// Move a playlist entry to a new index. [entryId] is the per-entry
  /// PlaylistItemId (not the underlying item id).
  Future<void> movePlaylistItem({
    required String baseUrl,
    required String token,
    required String playlistId,
    required String entryId,
    required int newIndex,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Playlists/$playlistId/Items/$entryId/Move/$newIndex',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// All studios/networks across the user's libraries.
  Future<List<BaseItemDto>> getStudios({
    required String baseUrl,
    required String userId,
    required String token,
  }) {
    return _getItems(
      '$baseUrl/Studios',
      token,
      query: {
        'UserId': userId,
        'SortBy': 'SortName',
        'Recursive': 'true',
      },
    );
  }

  /// All music artists.
  Future<List<BaseItemDto>> getArtists({
    required String baseUrl,
    required String userId,
    required String token,
  }) {
    return _getItems(
      '$baseUrl/Artists',
      token,
      query: {
        'UserId': userId,
        'SortBy': 'SortName',
        'Recursive': 'true',
        'Fields': 'PrimaryImageAspectRatio',
      },
    );
  }

  /// Live TV channels, each with its current program (for now-playing labels).
  Future<List<BaseItemDto>> getLiveTvChannels({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    return _getItems(
      '$baseUrl/LiveTv/Channels',
      token,
      query: {
        'UserId': userId,
        'EnableImages': 'true',
        'AddCurrentProgram': 'true',
        'Fields': 'PrimaryImageAspectRatio',
        'Limit': '1000',
      },
    );
  }

  /// Existing DVR recordings.
  Future<List<BaseItemDto>> getRecordings({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    return _getItems(
      '$baseUrl/LiveTv/Recordings',
      token,
      query: {
        'UserId': userId,
        'EnableImages': 'true',
        'Fields': 'Overview,PrimaryImageAspectRatio',
      },
    );
  }

  /// Schedules a recording for a program (single-program timer).
  Future<void> recordProgram({
    required String baseUrl,
    required String token,
    required String programId,
  }) async {
    try {
      final defaults = await _dio.get(
        '$baseUrl/LiveTv/Timers/Defaults',
        queryParameters: {'programId': programId},
        options: _authed(token),
      );
      await _dio.post(
        '$baseUrl/LiveTv/Timers',
        data: defaults.data,
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Schedules a recording for the whole series a program belongs to.
  Future<void> recordSeries({
    required String baseUrl,
    required String token,
    required String programId,
  }) async {
    try {
      final defaults = await _dio.get(
        '$baseUrl/LiveTv/SeriesTimers/Defaults',
        queryParameters: {'programId': programId},
        options: _authed(token),
      );
      await _dio.post(
        '$baseUrl/LiveTv/SeriesTimers',
        data: defaults.data,
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Cancels a scheduled recording timer.
  Future<void> cancelTimer({
    required String baseUrl,
    required String token,
    required String timerId,
  }) async {
    try {
      await _dio.delete('$baseUrl/LiveTv/Timers/$timerId',
          options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Programs (EPG entries) for the given channels within a time window.
  Future<List<BaseItemDto>> getGuidePrograms({
    required String baseUrl,
    required String userId,
    required String token,
    required List<String> channelIds,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/LiveTv/Programs',
        data: {
          'ChannelIds': channelIds,
          'UserId': userId,
          'MinStartDate': start.toUtc().toIso8601String(),
          'MaxStartDate': end.toUtc().toIso8601String(),
          'SortBy': ['StartDate'],
          // Ask for descriptions/genres so program detail isn't empty.
          // (EpisodeTitle is returned by default for programs; it is NOT a
          // valid ItemFields value and adding it 400s the whole request.)
          'Fields': ['Overview', 'Genres'],
          'EnableImages': false,
          'EnableTotalRecordCount': false,
        },
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['Items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BaseItemDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// The signed-in user, including their live policy (admin / delete rights).
  Future<UserDto> getCurrentUser({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Users/Me', options: _authed(token));
      return UserDto.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Full details for a single item (Overview, Genres, runtime, resume, ...).
  Future<BaseItemDto> getItem({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Users/$userId/Items/$itemId',
        options: _authed(token),
      );
      return BaseItemDto.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Titles similar to [itemId] ("More Like This").
  Future<List<BaseItemDto>> getSimilar({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    int limit = 16,
  }) async {
    return _getItems(
      '$baseUrl/Items/$itemId/Similar',
      token,
      query: {
        'UserId': userId,
        'Limit': '$limit',
        'Fields': 'PrimaryImageAspectRatio',
      },
    );
  }

  /// Sessions this user can remote-control (other Jellyfin players).
  Future<List<Map<String, dynamic>>> getControllableSessions({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    final all = await _getList('$baseUrl/Sessions', token, query: {
      'ControllableByUserId': userId,
      'ActiveWithinSeconds': '600',
    });
    return all.where((s) => s['SupportsRemoteControl'] == true).toList();
  }

  /// Starts playback of an item on another device.
  Future<void> playOnSession({
    required String baseUrl,
    required String token,
    required String sessionId,
    required String itemId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Sessions/$sessionId/Playing',
        queryParameters: {'playCommand': 'PlayNow', 'itemIds': itemId},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Sends a playstate command (PlayPause, Stop, NextTrack, …) to a device.
  Future<void> sessionPlaystate({
    required String baseUrl,
    required String token,
    required String sessionId,
    required String command,
  }) async {
    try {
      await _dio.post('$baseUrl/Sessions/$sessionId/Playing/$command',
          options: _authed(token));
    } on DioException {
      // Best-effort remote command.
    }
  }

  // --- SyncPlay (watch together) ---

  Future<List<Map<String, dynamic>>> getSyncPlayGroups({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/SyncPlay/List', options: _authed(token));
      final data = res.data;
      final listRaw = data is List ? data : const [];
      return listRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> syncPlayNew({
    required String baseUrl,
    required String token,
    required String groupName,
  }) async {
    try {
      await _dio.post('$baseUrl/SyncPlay/New',
          data: {'GroupName': groupName}, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> syncPlayJoin({
    required String baseUrl,
    required String token,
    required String groupId,
  }) async {
    try {
      await _dio.post('$baseUrl/SyncPlay/Join',
          data: {'GroupId': groupId}, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> syncPlayLeave({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/SyncPlay/Leave', options: _authed(token));
    } on DioException {
      // Best-effort.
    }
  }

  /// Group playback controls. These tell the SERVER what this client did, and
  /// the server broadcasts the coordinated command to every member (including
  /// us). All best-effort: a dropped control just misses one sync tick.
  Future<void> _syncPost(String baseUrl, String path, String token,
      [Object? data]) async {
    try {
      await _dio.post('$baseUrl/SyncPlay/$path',
          data: data, options: _authed(token));
    } on DioException {
      // Best-effort; SyncPlay tolerates a missed message.
    }
  }

  Future<void> syncPlayPause(
          {required String baseUrl, required String token}) =>
      _syncPost(baseUrl, 'Pause', token);

  Future<void> syncPlayUnpause(
          {required String baseUrl, required String token}) =>
      _syncPost(baseUrl, 'Unpause', token);

  Future<void> syncPlaySeek(
          {required String baseUrl,
          required String token,
          required int positionTicks}) =>
      _syncPost(baseUrl, 'Seek', token, {'PositionTicks': positionTicks});

  /// Set the group's queue to [itemId] at [startPositionTicks]. This is how a
  /// client tells the group WHAT to watch; every member then opens it. Without
  /// this the group has no shared content and pause/seek are meaningless.
  Future<void> syncPlaySetNewQueue({
    required String baseUrl,
    required String token,
    required List<String> playingQueue,
    required int playingItemPosition,
    required int startPositionTicks,
  }) =>
      _syncPost(baseUrl, 'SetNewQueue', token, {
        'PlayingQueue': playingQueue,
        'PlayingItemPosition': playingItemPosition,
        'StartPositionTicks': startPositionTicks,
      });

  /// Report that this client began buffering (so the group waits for it).
  Future<void> syncPlayBuffering({
    required String baseUrl,
    required String token,
    required int positionTicks,
    required bool isPlaying,
    required String whenIso,
    String? playlistItemId,
  }) =>
      _syncPost(baseUrl, 'Buffering', token, {
        'When': whenIso,
        'PositionTicks': positionTicks,
        'IsPlaying': isPlaying,
        if (playlistItemId != null) 'PlaylistItemId': playlistItemId,
      });

  /// Report that this client is ready to resume at [positionTicks].
  Future<void> syncPlayReady({
    required String baseUrl,
    required String token,
    required int positionTicks,
    required bool isPlaying,
    required String whenIso,
    String? playlistItemId,
  }) =>
      _syncPost(baseUrl, 'Ready', token, {
        'When': whenIso,
        'PositionTicks': positionTicks,
        'IsPlaying': isPlaying,
        if (playlistItemId != null) 'PlaylistItemId': playlistItemId,
      });

  /// Report this client's measured round-trip ping (ms) so the server can
  /// schedule commands accounting for its latency.
  Future<void> syncPlayPing(
          {required String baseUrl,
          required String token,
          required int pingMs}) =>
      _syncPost(baseUrl, 'Ping', token, {'Ping': pingMs});

  /// The server's clock, with reception/transmission stamps, for estimating the
  /// client-server time offset that SyncPlay's `When` scheduling needs.
  Future<Map<String, dynamic>?> getUtcTime({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/GetUtcTime', options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException {
      return null;
    }
  }

  // --- Administration (all require the user to be an administrator) ---

  Future<List<Map<String, dynamic>>> _getList(String url, String token,
      {Map<String, dynamic>? query, String? itemsKey}) async {
    try {
      final res = await _dio.get(url,
          queryParameters: query, options: _authed(token));
      final data = res.data;
      final list = itemsKey != null
          ? ((data as Map)[itemsKey] as List? ?? const [])
          : (data as List? ?? const []);
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<List<Map<String, dynamic>>> getUsers({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Users', token);

  Future<Map<String, dynamic>> getUser({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/Users/$userId', options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> updateUserPolicy({
    required String baseUrl,
    required String token,
    required String userId,
    required Map<String, dynamic> policy,
  }) async {
    try {
      await _dio.post('$baseUrl/Users/$userId/Policy',
          data: policy, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<Map<String, dynamic>> createUser({
    required String baseUrl,
    required String token,
    required String name,
    String? password,
  }) async {
    try {
      final res = await _dio.post('$baseUrl/Users/New',
          data: {
            'Name': name,
            if (password != null && password.isNotEmpty) 'Password': password,
          },
          options: _authed(token));
      return Map<String, dynamic>.from((res.data as Map?) ?? {});
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> deleteUser({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Users/$userId', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> setUserPassword({
    required String baseUrl,
    required String token,
    required String userId,
    String? newPassword,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Users/$userId/Password',
        data: newPassword == null || newPassword.isEmpty
            ? {'ResetPassword': true}
            : {'NewPw': newPassword},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<List<Map<String, dynamic>>> getVirtualFolders({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Library/VirtualFolders', token);

  /// Client devices that have connected to the server (admin only).
  Future<List<Map<String, dynamic>>> getDevices({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/Devices', options: _authed(token));
      final items = (res.data as Map)['Items'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Removes (deauthorizes) a client device by id (admin only).
  Future<void> deleteDevice({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete('$baseUrl/Devices',
          queryParameters: {'id': id}, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// The server's parental rating names and their numeric scores.
  Future<List<Map<String, dynamic>>> getParentalRatings({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Localization/ParentalRatings',
          options: _authed(token));
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// URL for an installed plugin's thumbnail image.
  String pluginImageUrl({required String baseUrl, required String pluginId}) =>
      '$baseUrl/Plugins/$pluginId/Image';

  /// A plugin's own configuration object (admin only). Throws if the plugin has
  /// no editable configuration.
  Future<Map<String, dynamic>> getPluginConfiguration({
    required String baseUrl,
    required String token,
    required String pluginId,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Plugins/$pluginId/Configuration',
          options: _authed(token));
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Writes back a plugin's configuration object (admin only).
  Future<void> updatePluginConfiguration({
    required String baseUrl,
    required String token,
    required String pluginId,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Plugins/$pluginId/Configuration',
        data: config,
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': 'application/json',
        }),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  // ---- Live TV administration ----

  /// Live TV info: tuner hosts, listing providers, and enabled state.
  Future<Map<String, dynamic>> getLiveTvInfo({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/LiveTv/Info', options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Adds a tuner host, e.g. {'Type': 'm3u', 'Url': '...'} or
  /// {'Type': 'hdhomerun', 'Url': 'http://ip'} (admin only).
  Future<void> addTunerHost({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> tuner,
  }) async {
    try {
      await _dio.post('$baseUrl/LiveTv/TunerHosts',
          data: tuner,
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          }));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Removes a tuner host by id (admin only).
  Future<void> deleteTunerHost({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete('$baseUrl/LiveTv/TunerHosts',
          queryParameters: {'id': id}, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Adds an XMLTV guide provider from a file path or URL (admin only).
  Future<void> addXmltvListingProvider({
    required String baseUrl,
    required String token,
    required String pathOrUrl,
  }) async {
    try {
      await _dio.post('$baseUrl/LiveTv/ListingProviders',
          queryParameters: {'validateListings': false},
          data: {'Type': 'xmltv', 'Path': pathOrUrl},
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          }));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Saves a guide (listings) provider. Mirrors the official dashboard: pass
  /// [validateLogin] when checking Schedules Direct credentials, and
  /// [validateListings] when committing a chosen lineup. Returns the saved
  /// provider (which carries the generated Id on first save).
  Future<Map<String, dynamic>> saveListingProvider({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> info,
    bool validateLogin = false,
    bool validateListings = false,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/LiveTv/ListingProviders',
        queryParameters: {
          'validateLogin': validateLogin,
          'validateListings': validateListings,
        },
        data: info,
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': 'application/json',
        }),
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// The Schedules Direct country list, grouped by region. Each entry carries a
  /// full name, short code, and a sample/regex for the postal code.
  Future<Map<String, dynamic>> getSchedulesDirectCountries({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/LiveTv/ListingProviders/SchedulesDirect/Countries',
        options: _authed(token),
      );
      final data = res.data;
      // The server proxies Schedules Direct's raw payload, which may arrive as
      // a JSON string rather than a decoded object.
      if (data is String) {
        return Map<String, dynamic>.from(jsonDecode(data) as Map);
      }
      return Map<String, dynamic>.from(data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Available lineups for a saved provider at a country + postal code.
  Future<List<({String id, String name})>> getListingProviderLineups({
    required String baseUrl,
    required String token,
    required String providerId,
    required String country,
    required String location,
    String type = 'SchedulesDirect',
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/LiveTv/ListingProviders/Lineups',
        queryParameters: {
          'id': providerId,
          'type': type,
          'location': location,
          'country': country,
        },
        options: _authed(token),
      );
      final list = (res.data as List?) ?? const [];
      return [
        for (final e in list.whereType<Map>())
          (id: '${e['Id'] ?? ''}', name: '${e['Name'] ?? e['Id'] ?? ''}'),
      ];
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Removes a guide provider by id (admin only).
  Future<void> deleteListingProvider({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete('$baseUrl/LiveTv/ListingProviders',
          queryParameters: {'id': id}, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  // ---- DVR: recordings, timers, and series rules ----

  /// Scheduled one-off recording timers.
  Future<List<Map<String, dynamic>>> getTimers({
    required String baseUrl,
    required String token,
  }) async {
    final res = await _dio.get('$baseUrl/LiveTv/Timers', options: _authed(token));
    return _itemsOf(res.data);
  }

  /// Series recording rules.
  Future<List<Map<String, dynamic>>> getSeriesTimers({
    required String baseUrl,
    required String token,
  }) async {
    final res =
        await _dio.get('$baseUrl/LiveTv/SeriesTimers', options: _authed(token));
    return _itemsOf(res.data);
  }

  /// A pre-filled timer for a program (channel, times, and default padding),
  /// ready to tweak and POST back as a one-off or series recording.
  Future<Map<String, dynamic>> getTimerDefaults({
    required String baseUrl,
    required String token,
    required String programId,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/LiveTv/Timers/Defaults',
          queryParameters: {'programId': programId}, options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> createTimer({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _dio.post('$baseUrl/LiveTv/Timers',
          data: timer,
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          }));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> createSeriesTimer({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _dio.post('$baseUrl/LiveTv/SeriesTimers',
          data: timer,
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          }));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> updateSeriesTimer({
    required String baseUrl,
    required String token,
    required String id,
    required Map<String, dynamic> timer,
  }) async {
    try {
      await _dio.post('$baseUrl/LiveTv/SeriesTimers/$id',
          data: timer,
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': 'application/json',
          }));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> cancelSeriesTimer({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete('$baseUrl/LiveTv/SeriesTimers/$id',
          options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> deleteRecording({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    try {
      await _dio.delete('$baseUrl/Items/$id', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  List<Map<String, dynamic>> _itemsOf(dynamic data) {
    final items = data is Map ? (data['Items'] as List? ?? const []) : const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Installed server plugins (admin).
  Future<List<Map<String, dynamic>>> getPlugins({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Plugins', token);

  Future<void> scanAllLibraries({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/Library/Refresh', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<List<Map<String, dynamic>>> getScheduledTasks({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/ScheduledTasks', token,
          query: {'isHidden': 'false'});

  Future<void> runScheduledTask({
    required String baseUrl,
    required String token,
    required String taskId,
  }) async {
    try {
      await _dio.post('$baseUrl/ScheduledTasks/Running/$taskId',
          options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<List<Map<String, dynamic>>> getSessions({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/Sessions', token);

  Future<List<Map<String, dynamic>>> getActivityLog({
    required String baseUrl,
    required String token,
  }) =>
      _getList('$baseUrl/System/ActivityLog/Entries', token,
          query: {'limit': '50'}, itemsKey: 'Items');

  Future<Map<String, dynamic>> getSystemInfo({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/System/Info', options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// The full server configuration (admin only). Includes the Quick Connect
  /// availability flag among many other settings.
  Future<Map<String, dynamic>> getServerConfiguration({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/System/Configuration',
          options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Writes back the full server configuration (admin only). Read it first,
  /// mutate the fields you need, then post the whole object.
  Future<void> updateServerConfiguration({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/System/Configuration',
        data: config,
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': 'application/json',
        }),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Available packages from the configured plugin repositories (admin only).
  Future<List<Map<String, dynamic>>> getPackages({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/Packages', options: _authed(token));
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Installs a plugin package by name (admin only). [version] and
  /// [repositoryUrl] are optional; the server picks the latest compatible
  /// version when omitted.
  Future<void> installPackage({
    required String baseUrl,
    required String token,
    required String name,
    required String guid,
    String? version,
    String? repositoryUrl,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Packages/Installed/${Uri.encodeComponent(name)}',
        queryParameters: {
          'assemblyGuid': guid,
          'version': ?version,
          'repositoryUrl': ?repositoryUrl,
        },
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Uninstalls an installed plugin by its id (admin only).
  Future<void> uninstallPlugin({
    required String baseUrl,
    required String token,
    required String pluginId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Plugins/$pluginId', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// The configured plugin repositories (admin only).
  Future<List<Map<String, dynamic>>> getRepositories({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/Repositories', options: _authed(token));
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Replaces the plugin repository list (admin only).
  Future<void> setRepositories({
    required String baseUrl,
    required String token,
    required List<Map<String, dynamic>> repositories,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Repositories',
        data: repositories,
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': 'application/json',
        }),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// A named configuration section (admin only), e.g. 'network' or 'encoding'.
  /// Branding: the login disclaimer, custom CSS, and the splash screen toggle.
  ///
  /// Branding is NOT part of ServerConfiguration — it has no 'Branding' key —
  /// so it has its own read and write. Reading it from the server config just
  /// yields null and shows the admin an empty form over a configured server.
  Future<Map<String, dynamic>> getBrandingConfiguration({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/Branding/Configuration',
          options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Writes branding back. Note the capitalised path segment: this is its own
  /// documented endpoint, not the generic named-configuration one.
  Future<void> updateBrandingConfiguration({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> branding,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/System/Configuration/Branding',
        data: branding,
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': 'application/json',
        }),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Lyrics for a track, timed when the source has timing.
  ///
  /// The server sources these itself — embedded .lrc, or a lyrics provider
  /// plugin (LrcLib and the like) — so there's no third-party call from here
  /// and nothing to key or rate-limit. 404 means this track simply has none,
  /// which is common and not an error.
  Future<SongLyrics?> getLyrics({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Audio/$itemId/Lyrics',
        options: Options(
          headers: {'Authorization': authHeader(token: token)},
          validateStatus: (s) => s == 200 || s == 404,
        ),
      );
      if (res.statusCode == 404 || res.data == null) return null;
      return SongLyrics.fromJson(res.data!);
    } on DioException {
      // Lyrics are a nicety; never let a failure disturb playback.
      return null;
    }
  }

  Future<Map<String, dynamic>> getNamedConfiguration({
    required String baseUrl,
    required String token,
    required String key,
  }) async {
    try {
      final res = await _dio.get('$baseUrl/System/Configuration/$key',
          options: _authed(token));
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Writes back a named configuration section (admin only).
  Future<void> updateNamedConfiguration({
    required String baseUrl,
    required String token,
    required String key,
    required Map<String, dynamic> config,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/System/Configuration/$key',
        data: config,
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': 'application/json',
        }),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// API keys granted to apps (admin only).
  Future<List<Map<String, dynamic>>> getApiKeys({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/Auth/Keys', options: _authed(token));
      final items = (res.data as Map)['Items'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Issues a new API key for [appName] (admin only).
  Future<void> createApiKey({
    required String baseUrl,
    required String token,
    required String appName,
  }) async {
    try {
      await _dio.post('$baseUrl/Auth/Keys',
          queryParameters: {'app': appName}, options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Revokes an API key (admin only).
  Future<void> deleteApiKey({
    required String baseUrl,
    required String token,
    required String key,
  }) async {
    try {
      await _dio.delete('$baseUrl/Auth/Keys/$key', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Available server log files (admin only).
  Future<List<Map<String, dynamic>>> getLogFiles({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final res =
          await _dio.get('$baseUrl/System/Logs', options: _authed(token));
      return (res.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// The contents of a named server log file (admin only).
  Future<String> getLogContent({
    required String baseUrl,
    required String token,
    required String name,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/System/Logs/Log',
        queryParameters: {'name': name},
        options: Options(
          headers: {'Authorization': authHeader(token: token)},
          responseType: ResponseType.plain,
        ),
      );
      return '${res.data}';
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Enables or disables Quick Connect server-wide (admin only) by toggling the
  /// `QuickConnectAvailable` flag in the server configuration.
  Future<void> setQuickConnectAvailable({
    required String baseUrl,
    required String token,
    required bool available,
  }) async {
    final config = await getServerConfiguration(baseUrl: baseUrl, token: token);
    config['QuickConnectAvailable'] = available;
    await updateServerConfiguration(
        baseUrl: baseUrl, token: token, config: config);
  }

  Future<void> restartServer({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/System/Restart', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> shutdownServer({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.post('$baseUrl/System/Shutdown', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> sendSessionMessage({
    required String baseUrl,
    required String token,
    required String sessionId,
    required String header,
    required String text,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Sessions/$sessionId/Message',
        data: {'Header': header, 'Text': text, 'TimeoutMs': 5000},
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Deletes an item from the server (requires delete permission).
  Future<void> deleteItem({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Items/$itemId', options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Triggers a metadata refresh for an item (requires permission).
  Future<void> refreshItem({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Items/$itemId/Refresh',
        queryParameters: {
          'metadataRefreshMode': 'FullRefresh',
          'imageRefreshMode': 'FullRefresh',
        },
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Marks an item played or unplayed.
  Future<void> setPlayed({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    required bool played,
  }) async {
    final url = '$baseUrl/Users/$userId/PlayedItems/$itemId';
    try {
      if (played) {
        await _dio.post(url, options: _authed(token));
      } else {
        await _dio.delete(url, options: _authed(token));
      }
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Adds or removes an item from favorites.
  Future<void> setFavorite({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    required bool favorite,
  }) async {
    final url = '$baseUrl/Users/$userId/FavoriteItems/$itemId';
    try {
      if (favorite) {
        await _dio.post(url, options: _authed(token));
      } else {
        await _dio.delete(url, options: _authed(token));
      }
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Skippable media segments (intro/credits/…) for an item. Empty when the
  /// server has no Media Segments provider — degrade gracefully, never throw.
  Future<List<MediaSegment>> getMediaSegments({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/MediaSegments/$itemId',
        options: _authed(token),
      );
      final items = (res.data['Items'] as List? ?? const []);
      return items
          .whereType<Map>()
          .map((e) => MediaSegment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException {
      return const [];
    }
  }

  /// The next episode to watch for a series, or null if none.
  Future<BaseItemDto?> getNextUp({
    required String baseUrl,
    required String userId,
    required String token,
    required String seriesId,
  }) async {
    try {
      final res = await _dio.get(
        '$baseUrl/Shows/NextUp',
        queryParameters: {
          'UserId': userId,
          'SeriesId': seriesId,
          'Limit': '1',
          'Fields': 'Overview,PrimaryImageAspectRatio',
        },
        options: _authed(token),
      );
      final items = (res.data['Items'] as List? ?? const []);
      if (items.isEmpty) return null;
      return BaseItemDto.fromJson(Map<String, dynamic>.from(items.first as Map));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Episodes for a series (optionally a single season), in order.
  Future<List<BaseItemDto>> getEpisodes({
    required String baseUrl,
    required String userId,
    required String token,
    required String seriesId,
    String? seasonId,
  }) async {
    return _getItems(
      '$baseUrl/Shows/$seriesId/Episodes',
      token,
      query: {
        'UserId': userId,
        'SeasonId': ?seasonId,
        'Fields': 'Overview,PrimaryImageAspectRatio',
      },
    );
  }

  /// Direct stream URL for a video. libmpv plays the original file; the server
  /// serves range requests so seeking works. Auth travels as the api_key param.
  String videoStreamUrl({
    required String baseUrl,
    required String itemId,
    required String token,
  }) {
    final params = {
      'static': 'true',
      'mediaSourceId': itemId,
      'api_key': token,
      'deviceId': deviceId,
    };
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Videos/$itemId/stream?$q';
  }

  /// Resolves a playable URL for a regular video via PlaybackInfo. With
  /// [forceTranscode] the server is told not to direct-play, so it returns an
  /// HLS transcode URL — the fallback for files libmpv can't play directly.
  Future<String> openVideoStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    bool forceTranscode = false,
    int? maxBitrate,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Items/$itemId/PlaybackInfo',
        queryParameters: {
          'UserId': userId,
          'MaxStreamingBitrate': '${maxBitrate ?? 120000000}',
          'EnableDirectPlay': forceTranscode ? 'false' : 'true',
          'EnableDirectStream': forceTranscode ? 'false' : 'true',
          'EnableTranscoding': 'true',
          'AllowVideoStreamCopy': 'true',
          'AllowAudioStreamCopy': 'true',
        },
        data: {'DeviceProfile': _videoDeviceProfile},
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final playSessionId = data['PlaySessionId'] as String?;
      final sources = (data['MediaSources'] as List?) ?? const [];
      if (sources.isEmpty) {
        throw JellyfinException('No playable source for this video.');
      }
      final ms = Map<String, dynamic>.from(sources.first as Map);
      final transcodingUrl = ms['TranscodingUrl'] as String?;
      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        return transcodingUrl.startsWith('http')
            ? transcodingUrl
            : '$baseUrl$transcodingUrl';
      }
      final params = {
        'static': 'true',
        'mediaSourceId': ?(ms['Id'] as String?),
        'playSessionId': ?playSessionId,
        'api_key': token,
        'deviceId': deviceId,
      };
      final q = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return '$baseUrl/Videos/$itemId/stream?$q';
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Resolves a Chromecast-playable stream for [itemId]. The server direct-plays
  /// when the source codecs fit a Cast device (returning the raw file URL and
  /// its container's MIME, so an h264/aac MKV casts as-is on a Chromecast with
  /// Google TV / Android TV), or hands back an HLS transcode URL when they don't.
  /// Returns the URL and the content type to give the Cast receiver.
  Future<({String url, String contentType})> castStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Items/$itemId/PlaybackInfo',
        queryParameters: {
          'UserId': userId,
          'MaxStreamingBitrate': '120000000',
          'EnableDirectPlay': 'true',
          'EnableDirectStream': 'true',
          'EnableTranscoding': 'true',
          'AllowVideoStreamCopy': 'true',
          'AllowAudioStreamCopy': 'true',
        },
        data: {'DeviceProfile': _castDeviceProfile},
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final playSessionId = data['PlaySessionId'] as String?;
      final sources = (data['MediaSources'] as List?) ?? const [];
      if (sources.isEmpty) {
        throw JellyfinException('No playable source for this video.');
      }
      final ms = Map<String, dynamic>.from(sources.first as Map);
      final transcodingUrl = ms['TranscodingUrl'] as String?;
      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        final url = transcodingUrl.startsWith('http')
            ? transcodingUrl
            : '$baseUrl$transcodingUrl';
        return (url: url, contentType: 'application/x-mpegurl');
      }
      final container =
          (ms['Container'] as String?)?.split(',').first.trim().toLowerCase();
      final params = {
        'static': 'true',
        'mediaSourceId': ?(ms['Id'] as String?),
        'playSessionId': ?playSessionId,
        'api_key': token,
        'deviceId': deviceId,
      };
      final q = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return (
        url: '$baseUrl/Videos/$itemId/stream?$q',
        contentType: _mimeForContainer(container),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  static String _mimeForContainer(String? c) {
    switch (c) {
      case 'mp4':
      case 'm4v':
      case 'mov':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'ts':
      case 'mpegts':
      case 'm2ts':
        return 'video/mp2t';
      default:
        return 'video/mp4';
    }
  }

  /// Opens a live stream for a channel via PlaybackInfo (the handshake HDHomeRun
  /// and most tuners require). Returns the playable URL plus the ids needed to
  /// close it later (freeing the tuner). Falls back to letting the server choose
  /// the source if our device profile trips it up.
  Future<LiveStreamHandle> openLiveStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String channelId,
  }) async {
    // On mobile, media_kit can't play a raw broadcast MPEG-TS the way desktop
    // libmpv does, so drop the direct-play profiles to force the server down its
    // HLS h264/aac transcode path (which media_kit plays on Android/iOS).
    final profile = (Platform.isAndroid || Platform.isIOS)
        ? {..._liveDeviceProfile, 'DirectPlayProfiles': const <Map>[]}
        : _liveDeviceProfile;
    try {
      return await _requestLiveStream(
        baseUrl: baseUrl,
        userId: userId,
        token: token,
        channelId: channelId,
        deviceProfile: profile,
      );
    } on JellyfinException {
      // Some channels 500 with a custom profile but work when the server picks.
      return _requestLiveStream(
        baseUrl: baseUrl,
        userId: userId,
        token: token,
        channelId: channelId,
        deviceProfile: null,
      );
    }
  }

  /// Closes a previously opened live stream so the tuner is released. Without
  /// this, opening a few channels exhausts the tuners and further opens 500.
  Future<void> closeLiveStream({
    required String baseUrl,
    required String token,
    required String liveStreamId,
    String? playSessionId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveStreams/Close',
        queryParameters: {'liveStreamId': liveStreamId},
        options: _authed(token),
      );
    } on DioException {
      // Best-effort.
    }
    // /Videos/ActiveEncodings used to live here. It is not part of the
    // Jellyfin API any more (checked against the published OpenAPI spec: no
    // such path), so it 404'd every time and released nothing. The transcode
    // is torn down by reporting Stopped WITH the LiveStreamId and
    // PlaySessionId, which reportPlaybackStopped now does.
  }

  Future<LiveStreamHandle> _requestLiveStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String channelId,
    required Map<String, dynamic>? deviceProfile,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Items/$channelId/PlaybackInfo',
        queryParameters: {
          'UserId': userId,
          'StartTimeTicks': '0',
          'IsPlayback': 'true',
          'AutoOpenLiveStream': 'true',
          'MaxStreamingBitrate': '120000000',
        },
        data: deviceProfile != null
            ? {'DeviceProfile': deviceProfile}
            : <String, dynamic>{},
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final playSessionId = data['PlaySessionId'] as String?;
      final sources = (data['MediaSources'] as List?) ?? const [];
      if (sources.isEmpty) {
        throw JellyfinException('No playable source for this channel.');
      }
      final ms = Map<String, dynamic>.from(sources.first as Map);
      final liveStreamId = ms['LiveStreamId'] as String?;

      final transcodingUrl = ms['TranscodingUrl'] as String?;
      final String url;
      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        url = transcodingUrl.startsWith('http')
            ? transcodingUrl
            : '$baseUrl$transcodingUrl';
      } else {
        final params = {
          'static': 'true',
          'mediaSourceId': ?(ms['Id'] as String?),
          'liveStreamId': ?liveStreamId,
          'playSessionId': ?playSessionId,
          'api_key': token,
          'deviceId': deviceId,
        };
        final q = params.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
        url = '$baseUrl/Videos/$channelId/stream?$q';
      }
      return LiveStreamHandle(
        url: url,
        liveStreamId: liveStreamId ?? (ms['Id'] as String?),
        playSessionId: playSessionId,
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  // General video profile. libmpv plays essentially every container, codec and
  // subtitle format, so advertise a wide direct-play set and declare embedded
  // subtitle support. Without this (the old code reused the narrow live-TV
  // profile below, which had no subtitle profiles), Jellyfin would fall back to
  // a full HLS transcode for many files the client can actually play directly,
  // which is what made startup and seeking slow.
  // What a modern Cast device (Chromecast with Google TV / Android TV) plays
  // directly. Broad enough that an h264/aac MKV direct-plays (cast as-is), while
  // codecs a Chromecast can't handle fall back to an h264/aac HLS transcode.
  static const _castDeviceProfile = {
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'mp4,mkv,webm,m4v,mov',
        'VideoCodec': 'h264,hevc,vp8,vp9',
        'AudioCodec': 'aac,mp3,ac3,eac3,opus,vorbis,flac',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,mp3',
        'Context': 'Streaming',
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
    ],
  };

  static const _videoDeviceProfile = {
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container':
            'mp4,m4v,mkv,webm,mov,avi,flv,ts,m2ts,mts,mpegts,wmv,asf,3gp,3g2,'
                'ogv,ogm,mpg,mpeg,vob,divx,dvr-ms,f4v,rm,rmvb',
        'VideoCodec':
            'h264,hevc,h265,mpeg2video,mpeg4,msmpeg4v3,vc1,vp8,vp9,av1,theora,'
                'wmv1,wmv2,wmv3,prores,dv,mjpeg',
        'AudioCodec':
            'aac,ac3,eac3,mp3,mp2,opus,flac,vorbis,dts,dca,truehd,mlp,alac,pcm,'
                'pcm_s16le,pcm_s24le,pcm_dvd,wmav2,wmapro,wmavoice,nellymoser,'
                'speex,amr_nb,amr_wb,ape,tta,wavpack',
      },
      {
        'Type': 'Audio',
        'Container':
            'mp3,aac,m4a,m4b,flac,alac,ogg,oga,opus,wav,wma,ape,wv,mka,tak,'
                'dsf,dff,mpc',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264,hevc',
        'AudioCodec': 'aac,ac3,eac3,mp3',
        'Context': 'Streaming',
      },
      {
        'Type': 'Audio',
        'Container': 'mp3',
        'AudioCodec': 'mp3',
        'Protocol': 'http',
        'Context': 'Streaming',
      },
    ],
    // Declaring these as Embed/External stops the server from burning subtitles
    // into the video (which forces a transcode); libmpv renders them itself.
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'Embed'},
      {'Format': 'subrip', 'Method': 'Embed'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'vtt', 'Method': 'Embed'},
      {'Format': 'webvtt', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
      {'Format': 'dvbsub', 'Method': 'Embed'},
      {'Format': 'sub', 'Method': 'Embed'},
      {'Format': 'idx', 'Method': 'Embed'},
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'subrip', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
    ],
  };

  // Broad direct-play profile: libmpv plays these, so the server hands back a
  // direct stream (remuxing to HLS only when it must).
  static const _liveDeviceProfile = {
    'MaxStreamingBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts,mkv,mp4,m4v,avi,mov,webm,flv',
        'VideoCodec': 'h264,hevc,mpeg2video,mpeg4,vc1,vp9,av1',
        'AudioCodec': 'aac,ac3,eac3,mp3,mp2,opus,flac,vorbis,dts',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,mp3',
        'Context': 'Streaming',
      },
    ],
    // Without any SubtitleProfiles the server has no plan to deliver captions on
    // a live channel, so nothing renders when you enable CC. Declaring the same
    // Embed/External support the VOD profile uses tells the server to keep the
    // subtitle stream in the container (DVB/teletext/608 caption streams
    // included) for libmpv to render, instead of dropping it.
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'Embed'},
      {'Format': 'subrip', 'Method': 'Embed'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'vtt', 'Method': 'Embed'},
      {'Format': 'webvtt', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
      {'Format': 'dvbsub', 'Method': 'Embed'},
      {'Format': 'dvb_teletext', 'Method': 'Embed'},
      {'Format': 'eia_608', 'Method': 'Embed'},
      {'Format': 'eia_708', 'Method': 'Embed'},
      {'Format': 'cc_dec', 'Method': 'Embed'},
      {'Format': 'sub', 'Method': 'Embed'},
      {'Format': 'idx', 'Method': 'Embed'},
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'subrip', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
    ],
  };

  /// Direct audio stream URL. libmpv plays the original file.
  String audioStreamUrl({
    required String baseUrl,
    required String itemId,
    required String token,
  }) {
    final params = {
      'static': 'true',
      'api_key': token,
      'deviceId': deviceId,
    };
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Audio/$itemId/stream?$q';
  }

  /// An audio-only HLS stream of [itemId]'s primary audio track, for casting a
  /// video's audio to an audio-only speaker (Nest/Home Mini) which can't render
  /// a video stream. Uses the universal audio endpoint, which extracts and
  /// transcodes the audio to AAC-in-HLS.
  String castAudioUrl({
    required String baseUrl,
    required String userId,
    required String itemId,
    required String token,
  }) {
    // A plain progressive MP3 stream, which Google speakers play the most
    // reliably (HLS-in-TS tended to load but never start on a Nest/Home Mini).
    final params = {
      'UserId': userId,
      'DeviceId': deviceId,
      'api_key': token,
      'AudioCodec': 'mp3',
      'Container': 'mp3',
      'MaxStreamingBitrate': '320000',
    };
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Audio/$itemId/universal?$q';
  }

  Future<void> reportPlaybackStart({
    required String baseUrl,
    required String token,
    required String itemId,
    required int positionTicks,
  }) =>
      _postPlayState('$baseUrl/Sessions/Playing', token, itemId, positionTicks);

  Future<void> reportPlaybackProgress({
    required String baseUrl,
    required String token,
    required String itemId,
    required int positionTicks,
  }) =>
      _postPlayState(
          '$baseUrl/Sessions/Playing/Progress', token, itemId, positionTicks);

  /// Tells the server playback ended.
  ///
  /// [liveStreamId] and [playSessionId] are not optional extras for Live TV:
  /// they are how the server knows WHICH live session ended, and without them
  /// it leaves the tuner and any transcode running. On an HDHomeRun that means
  /// the 2-stream limit is reached after a couple of channel changes and every
  /// further tune-in 500s.
  Future<void> reportPlaybackStopped({
    required String baseUrl,
    required String token,
    required String itemId,
    required int positionTicks,
    String? liveStreamId,
    String? playSessionId,
  }) =>
      _postPlayState(
        '$baseUrl/Sessions/Playing/Stopped',
        token,
        itemId,
        positionTicks,
        liveStreamId: liveStreamId,
        playSessionId: playSessionId,
      );

  Future<void> _postPlayState(
    String url,
    String token,
    String itemId,
    int positionTicks, {
    String? liveStreamId,
    String? playSessionId,
  }) async {
    try {
      await _dio.post(
        url,
        data: {
          'ItemId': itemId,
          'MediaSourceId': itemId,
          'PositionTicks': positionTicks,
          'CanSeek': true,
          'PlayMethod': 'DirectStream',
          'LiveStreamId': ?liveStreamId,
          'PlaySessionId': ?playSessionId,
        },
        options: _authed(token),
      );
    } on DioException {
      // Progress reporting is best-effort; never let it break playback.
    }
  }

  /// Builds an image URL for an item. Load it with [imageHeaders] for auth.
  String imageUrl({
    required String baseUrl,
    required String itemId,
    String type = 'Primary',
    String? tag,
    int? maxHeight,
    int? maxWidth,
  }) {
    final params = <String, String>{'quality': '90'};
    if (tag != null) params['tag'] = tag;
    if (maxHeight != null) params['fillHeight'] = '$maxHeight';
    if (maxWidth != null) params['fillWidth'] = '$maxWidth';
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Items/$itemId/Images/$type?$q';
  }

  /// URL for one trickplay tile sheet (a grid of scrub-preview thumbnails).
  /// [width] is the resolution key from the item's trickplay geometry.
  String trickplayTileUrl({
    required String baseUrl,
    required String itemId,
    required int width,
    required int tileIndex,
  }) {
    return '$baseUrl/Videos/$itemId/Trickplay/$width/$tileIndex.jpg';
  }

  /// URL for a user's avatar (profile image). Returns null when the user has
  /// no primary image set.
  String? userImageUrl({
    required String baseUrl,
    required String userId,
    String? tag,
    int? size,
  }) {
    if (tag == null) return null;
    final params = <String, String>{'tag': tag, 'quality': '90'};
    if (size != null) params['fillHeight'] = '$size';
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Users/$userId/Images/Primary?$q';
  }

  /// Upload a user's avatar. Jellyfin expects the image bytes base64-encoded in
  /// the request body with the image mime type as Content-Type.
  Future<void> uploadUserImage({
    required String baseUrl,
    required String token,
    required String userId,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    try {
      final b64 = base64Encode(bytes);
      await _dio.post(
        '$baseUrl/Users/$userId/Images/Primary',
        data: b64,
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': contentType,
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  Future<void> deleteUserImage({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    try {
      await _dio.delete('$baseUrl/Users/$userId/Images/Primary',
          options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// URL for the server's custom splash screen image.
  String splashscreenUrl({required String baseUrl}) =>
      '$baseUrl/Branding/Splashscreen';

  /// Uploads a custom splash screen image (admin only).
  Future<void> uploadSplashscreen({
    required String baseUrl,
    required String token,
    required List<int> bytes,
    String contentType = 'image/png',
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Branding/Splashscreen',
        data: base64Encode(bytes),
        options: Options(headers: {
          'Authorization': authHeader(token: token),
          'Content-Type': contentType,
        }),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  /// Removes the custom splash screen image (admin only).
  Future<void> deleteSplashscreen({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.delete('$baseUrl/Branding/Splashscreen',
          options: _authed(token));
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e));
    }
  }

  String _friendlyDioError(DioException e, {bool connecting = false}) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Check the address and '
            'that the server is running.';
      case DioExceptionType.connectionError:
        return connecting
            ? 'Could not reach that server. Check the address, port, and your '
                'network connection.'
            : 'Lost connection to the server.';
      case DioExceptionType.badCertificate:
        return "The server's security certificate could not be verified.";
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) {
          return connecting
              ? 'No Jellyfin server was found at that address.'
              : 'The requested resource was not found (404).';
        }
        return 'The server returned an error (${code ?? 'unknown'}).';
      default:
        return 'Something went wrong talking to the server.';
    }
  }
}

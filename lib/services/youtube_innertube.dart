import 'package:dio/dio.dart';

import '../models/youtube_channel.dart';
import '../models/youtube_chapter.dart';
import '../models/youtube_comment.dart';
import '../models/youtube_playlist.dart';
import '../models/youtube_video.dart';
import '../models/youtube_watch.dart';
import 'youtube_search_params.dart';

/// One page of comments, plus the total count as YouTube renders it.
class YtCommentsPage {
  final List<YoutubeComment> comments;
  final String? continuation;
  final String countLabel; // e.g. "2,769"
  const YtCommentsPage({
    this.comments = const [],
    this.continuation,
    this.countLabel = '',
  });
}

/// One page of search results. [continuation] is the token for the next page,
/// or null when there are no more.
class YtSearchPage {
  final List<YoutubeVideo> videos;
  final List<YoutubeChannel> channels;
  final List<YoutubePlaylist> playlists;
  final String? continuation;
  const YtSearchPage({
    this.videos = const [],
    this.channels = const [],
    this.playlists = const [],
    this.continuation,
  });

  bool get isEmpty => videos.isEmpty && channels.isEmpty && playlists.isEmpty;
}

/// Talks to YouTube's InnerTube API, the same endpoint NewPipe uses.
///
/// youtube_explode's own search scrapes the HTML results page and its parser
/// throws (NoSuchMethodError on `getT`) whenever the results include a channel
/// card. InnerTube returns structured JSON instead, so this owns search and the
/// watch page, and leaves the library to do streams and channel uploads.
class YoutubeInnerTube {
  /// Language and country YouTube tailors results to (InnerTube hl/gl). These
  /// were hardcoded to en/US, which quietly served American English results to
  /// everyone.
  final String language;
  final String country;

  /// YouTube's Restricted Mode. Filtering is server-side — this asks YouTube to
  /// apply its own judgement rather than guessing locally at what's mature.
  final bool restrictedMode;

  static const _searchEndpoint = 'https://www.youtube.com/youtubei/v1/search';
  static const _nextEndpoint = 'https://www.youtube.com/youtubei/v1/next';
  static const _browseEndpoint = 'https://www.youtube.com/youtubei/v1/browse';

  // The public web client identity InnerTube expects.
  static const _clientName = 'WEB';
  static const _clientVersion = '2.20240726.00.00';

  // Protobuf filter meaning "type = video", so channel/playlist cards never
  // appear in the response.

  final Dio _dio;

  YoutubeInnerTube({
    this.language = 'en',
    this.country = 'US',
    this.restrictedMode = false,
    Dio? dio,
  })
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'Content-Type': 'application/json',
                'Accept-Language': 'en-US,en;q=0.9',
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
              },
            ));

  Map<String, dynamic> get _context => {
        'client': {
          'clientName': _clientName,
          'clientVersion': _clientVersion,
          'hl': language,
          'gl': country,
        },
        if (restrictedMode) 'user': {'enableSafetyMode': true},
      };

  /// First page of results, plus the token used to fetch the next one.
  Future<YtSearchPage> search(
    String query, {
    YtSearchFilter filter = YtSearchFilter.videos,
    YtSearchSort sort = YtSearchSort.relevance,
    YtUploadDate uploadDate = YtUploadDate.any,
    YtDuration duration = YtDuration.any,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _searchEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {
        'context': _context,
        'query': query,
        'params': YoutubeSearchParams.build(
          filter: filter,
          sort: sort,
          uploadDate: uploadDate,
          duration: duration,
        ),
      },
    );
    final data = res.data;
    if (data == null) return const YtSearchPage();
    final sections = _path(data, [
      'contents',
      'twoColumnSearchResultsRenderer',
      'primaryContents',
      'sectionListRenderer',
      'contents',
    ]);
    return _page(sections);
  }

  /// A further page of results for a token from a previous [search].
  Future<YtSearchPage> searchMore(String continuation) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _searchEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {'context': _context, 'continuation': continuation},
    );
    final data = res.data;
    if (data == null) return const YtSearchPage();
    // Continuations arrive under a different root than the first page.
    final commands = _path(data, ['onResponseReceivedCommands']);
    if (commands is! List) return const YtSearchPage();
    final videos = <YoutubeVideo>[];
    String? token;
    for (final c in commands) {
      final items =
          _path(c, ['appendContinuationItemsAction', 'continuationItems']);
      if (items is! List) continue;
      final page = _page(items);
      videos.addAll(page.videos);
      token ??= page.continuation;
    }
    return YtSearchPage(videos: videos, continuation: token);
  }

  /// Both the first page and continuations are lists of sections, each either
  /// an item section of results or the token for the next page.
  YtSearchPage _page(dynamic sections) {
    if (sections is! List) return const YtSearchPage();
    final videos = <YoutubeVideo>[];
    final channels = <YoutubeChannel>[];
    final playlists = <YoutubePlaylist>[];
    String? token;
    for (final section in sections) {
      final items = _path(section, ['itemSectionRenderer', 'contents']);
      if (items is List) {
        for (final item in items) {
          if (item is! Map) continue;

          final v = item['videoRenderer'];
          if (v is Map) {
            final parsed = _video(Map<String, dynamic>.from(v));
            if (parsed != null) videos.add(parsed);
            continue;
          }

          final c = item['channelRenderer'];
          if (c is Map) {
            final parsed = _channel(Map<String, dynamic>.from(c));
            if (parsed != null) channels.add(parsed);
            continue;
          }

          // Playlists come back as lockupViewModel now, not playlistRenderer.
          final l = item['lockupViewModel'];
          if (l is Map &&
              '${l['contentType']}' == 'LOCKUP_CONTENT_TYPE_PLAYLIST') {
            final parsed = _playlist(Map<String, dynamic>.from(l));
            if (parsed != null) playlists.add(parsed);
          }
          // Anything else — ads, shelves, people-also-watched — is skipped.
        }
      }
      final t = _path(section, [
        'continuationItemRenderer',
        'continuationEndpoint',
        'continuationCommand',
        'token',
      ]);
      if (t is String) token = t;
    }
    return YtSearchPage(
      videos: videos,
      channels: channels,
      playlists: playlists,
      continuation: token,
    );
  }

  /// A Short.
  ///
  /// Shorts do NOT use lockupViewModel like everything else — they have their
  /// own shortsLockupViewModel, with the title under overlayMetadata and the
  /// thumbnail nested twice. Parsing the Shorts tab with the ordinary lockup
  /// reader finds nothing and reports an empty tab on a channel with 48 shorts.
  YoutubeVideo? _shortsLockup(Map<String, dynamic> s) {
    final id = _path(s, ['onTap', 'innertubeCommand', 'reelWatchEndpoint', 'videoId']) ??
        _path(s, ['onTap', 'reelWatchEndpoint', 'videoId']) ??
        _firstVideoId(s);
    if (id is! String || id.isEmpty) return null;

    final title = _text(_path(s, ['overlayMetadata', 'primaryText']));
    if (title.isEmpty) return null;

    final sources =
        _path(s, ['thumbnailViewModel', 'thumbnailViewModel', 'image', 'sources']);
    var thumb = '';
    if (sources is List && sources.isNotEmpty) {
      final url = (sources.first as Map)['url'];
      if (url is String) thumb = url;
    }

    return YoutubeVideo(
      id: id,
      title: title,
      author: '',
      url: 'https://www.youtube.com/watch?v=$id',
      thumbnailUrl: thumb,
      // Shorts have no duration; isShort keeps them off the LIVE badge.
      isShort: true,
      uploadedLabel: '',
      viewCount: _viewsFromLabel(_text(_path(s, ['overlayMetadata', 'secondaryText']))),
    );
  }

  /// The first videoId anywhere in the node. The onTap command shape shifts
  /// between clients, and the id is the one thing a Short must have.
  String? _firstVideoId(dynamic node) {
    String? found;
    void walk(dynamic n) {
      if (found != null) return;
      if (n is Map) {
        for (final e in n.entries) {
          if (e.key == 'videoId' && e.value is String) {
            found = e.value as String;
            return;
          }
          walk(e.value);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(node);
    return found;
  }

  /// "299K views" -> 299000. Shorts only ever give the rounded label.
  int? _viewsFromLabel(String label) {
    final m = RegExp(r'([\d.,]+)\s*([KMB])?', caseSensitive: false)
        .firstMatch(label.trim());
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (n == null) return null;
    return switch (m.group(2)?.toUpperCase()) {
      'K' => (n * 1000).round(),
      'M' => (n * 1000000).round(),
      'B' => (n * 1000000000).round(),
      _ => n.round(),
    };
  }

  /// One of a channel's tabs.
  ///
  /// [isRequestedTab] is load-bearing: when a channel has no such tab, YouTube
  /// does not error — it quietly returns the Home feed instead. A channel with
  /// no live streams asked for "streams" comes back with its ordinary videos
  /// and selected tab "Home", so rendering the response as-is shows regular
  /// uploads under a Live heading. The caller uses this to show nothing.
  Future<YtChannelTab> channelTab(String channelId, YtChannelTabKind kind) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _browseEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {
        'context': _context,
        'browseId': channelId,
        'params': kind.params,
      },
    );
    final data = res.data;
    if (data == null) return const YtChannelTab();

    // Which tabs this channel actually has, and which one answered.
    final tabs = _path(data, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs']);
    var selected = '';
    final available = <String>{};
    if (tabs is List) {
      for (final t in tabs) {
        final title = '${_path(t, ['tabRenderer', 'title']) ?? ''}';
        if (title.isEmpty) continue;
        available.add(title);
        if (_path(t, ['tabRenderer', 'selected']) == true) selected = title;
      }
    }
    final matched = selected.toLowerCase() == kind.title.toLowerCase();

    final videos = <YoutubeVideo>[];
    final playlists = <YoutubePlaylist>[];
    if (matched) {
      // Shorts have their own renderer entirely.
      for (final s in _findAll(data, 'shortsLockupViewModel')) {
        final v = _shortsLockup(Map<String, dynamic>.from(s as Map));
        if (v != null) videos.add(v);
      }
      for (final l in _findAll(data, 'lockupViewModel')) {
        final map = Map<String, dynamic>.from(l as Map);
        switch ('${map['contentType']}') {
          case 'LOCKUP_CONTENT_TYPE_VIDEO':
            final v = _lockup(map);
            if (v != null) videos.add(v);
          case 'LOCKUP_CONTENT_TYPE_PLAYLIST':
            final p = _playlist(map);
            if (p != null) playlists.add(p);
        }
      }
    }

    return YtChannelTab(
      videos: videos,
      playlists: playlists,
      availableTabs: available,
      isRequestedTab: matched,
      continuation: matched ? _continuationToken(data) : null,
    );
  }

  /// A further page of a channel tab, for a token from [channelTab]. Returns
  /// full video metadata in a single request, so paging a channel costs one
  /// request per page rather than one per video.
  Future<YtChannelTab> channelTabMore(String continuation) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _browseEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {'context': _context, 'continuation': continuation},
    );
    final data = res.data;
    if (data == null) return const YtChannelTab();
    final videos = <YoutubeVideo>[];
    for (final s in _findAll(data, 'shortsLockupViewModel')) {
      final v = _shortsLockup(Map<String, dynamic>.from(s as Map));
      if (v != null) videos.add(v);
    }
    for (final l in _findAll(data, 'lockupViewModel')) {
      final map = Map<String, dynamic>.from(l as Map);
      if ('${map['contentType']}' == 'LOCKUP_CONTENT_TYPE_VIDEO') {
        final v = _lockup(map);
        if (v != null) videos.add(v);
      }
    }
    return YtChannelTab(
      videos: videos,
      isRequestedTab: true,
      continuation: _continuationToken(data),
    );
  }

  /// The next-page token embedded in a browse response, if any.
  String? _continuationToken(dynamic data) {
    for (final c in _findAll(data, 'continuationCommand')) {
      if (c is Map) {
        final t = c['token'];
        if (t is String && t.isNotEmpty) return t;
      }
    }
    return null;
  }

  /// Every value under [key], at any depth. The browse response nests its
  /// items differently per tab, and chasing each shape is brittle.
  List<dynamic> _findAll(dynamic node, String key) {
    final out = <dynamic>[];
    void walk(dynamic n) {
      if (n is Map) {
        for (final e in n.entries) {
          if (e.key == key) out.add(e.value);
          walk(e.value);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(node);
    return out;
  }

  /// Chapters, from the marker entities in the batch update.
  ///
  /// Two marker lists arrive and they must not be confused:
  /// MARKER_TYPE_HEATMAP is the "most replayed" graph — around a hundred evenly
  /// spaced markers with no titles — while MARKER_TYPE_TIMESTAMPS is the actual
  /// chapter list. Taking the wrong one yields a hundred untitled "chapters".
  ///
  /// startMillis is read directly rather than parsing the "4:15" display label,
  /// which is rounded and localised.
  List<YoutubeChapter> _chapters(Map<String, dynamic> data) {
    final mutations = _path(data, [
      'frameworkUpdates',
      'entityBatchUpdate',
      'mutations',
    ]);
    if (mutations is! List) return const [];

    for (final m in mutations) {
      final list = _path(m, ['payload', 'macroMarkersListEntity', 'markersList']);
      if (list is! Map) continue;
      if ('${list['markerType']}' != 'MARKER_TYPE_TIMESTAMPS') continue;

      final markers = list['markers'];
      if (markers is! List) continue;
      final out = <YoutubeChapter>[];
      for (final marker in markers.whereType<Map>()) {
        final title = _text(marker['title']);
        final startMillis = int.tryParse('${marker['startMillis'] ?? ''}');
        if (title.isEmpty || startMillis == null) continue;
        out.add(YoutubeChapter(
          title: title,
          start: Duration(milliseconds: startMillis),
        ));
      }
      if (out.isNotEmpty) {
        out.sort((a, b) => a.start.compareTo(b.start));
        return out;
      }
    }
    return const [];
  }

  /// A channel search result.
  ///
  /// Mind the field names, they are not what they say: YouTube puts the
  /// subscriber count ("1.26M subscribers") in videoCountText, and the @handle
  /// in subscriberCountText. Verified against the live endpoint.
  YoutubeChannel? _channel(Map<String, dynamic> c) {
    final id = c['channelId'];
    if (id is! String || id.isEmpty) return null;
    final title = _text(c['title']);
    final thumb = _path(c, ['thumbnail', 'thumbnails']);
    var logo = '';
    if (thumb is List && thumb.isNotEmpty) {
      final url = (thumb.last as Map)['url'];
      if (url is String) logo = url.startsWith('//') ? 'https:$url' : url;
    }
    return YoutubeChannel(
      id: id,
      title: title,
      logoUrl: logo,
      subscribersText: _text(c['videoCountText']),
      handle: _text(c['subscriberCountText']),
    );
  }

  YoutubePlaylist? _playlist(Map<String, dynamic> l) {
    final id = l['contentId'];
    if (id is! String || id.isEmpty) return null;
    final md = _path(l, ['metadata', 'lockupMetadataViewModel']);
    final title = md is Map ? _text(_path(md, ['title'])) : '';
    if (title.isEmpty) return null;

    var thumb = '';
    final sources = _path(l, [
      'contentImage',
      'collectionThumbnailViewModel',
      'primaryThumbnail',
      'thumbnailViewModel',
      'image',
      'sources',
    ]);
    if (sources is List && sources.isNotEmpty) {
      final url = (sources.first as Map)['url'];
      if (url is String) thumb = url;
    }

    // The owner is the first metadata row; the video count is a badge drawn
    // over the thumbnail ("22 videos"), not a metadata row.
    var author = '';
    final rows = md is Map
        ? _path(md, ['metadata', 'contentMetadataViewModel', 'metadataRows'])
        : null;
    if (rows is List) {
      outer:
      for (final row in rows) {
        final parts = _path(row, ['metadataParts']);
        if (parts is! List) continue;
        for (final p in parts) {
          final t = _text(_path(p, ['text']));
          // 'Playlist' is a type label, not an owner.
          if (t.isNotEmpty && t != 'Playlist') {
            author = t;
            break outer;
          }
        }
      }
    }

    var count = '';
    final overlays = _path(l, [
      'contentImage',
      'collectionThumbnailViewModel',
      'primaryThumbnail',
      'thumbnailViewModel',
      'overlays',
    ]);
    if (overlays is List) {
      for (final o in overlays) {
        final badges =
            _path(o, ['thumbnailOverlayBadgeViewModel', 'thumbnailBadges']);
        if (badges is! List) continue;
        for (final b in badges) {
          final t = _path(b, ['thumbnailBadgeViewModel', 'text']);
          if (t is String && t.isNotEmpty) {
            count = t;
            break;
          }
        }
        if (count.isNotEmpty) break;
      }
    }

    return YoutubePlaylist(
      id: id,
      title: title,
      thumbnailUrl: thumb,
      author: author,
      videoCountLabel: count,
    );
  }

  /// Video metadata + related videos for the watch page, in one call.
  Future<YoutubeWatchDetails> watch(String videoId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _nextEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {'context': _context, 'videoId': videoId},
    );
    final data = res.data ?? const <String, dynamic>{};

    var title = '';
    var views = '';
    var date = '';
    var channelName = '';
    String? channelId;
    String? avatar;
    var subs = '';
    var description = '';
    String? commentsToken;

    final sections = _path(data, [
      'contents',
      'twoColumnWatchNextResults',
      'results',
      'results',
      'contents',
    ]);
    if (sections is List) {
      for (final s in sections) {
        if (s is! Map) continue;
        // The watch page already carries the token for the comments section,
        // so grab it here rather than re-fetching this page later.
        if (_path(s, ['itemSectionRenderer', 'sectionIdentifier']) ==
            'comment-item-section') {
          final t = _path(s, [
            'itemSectionRenderer',
            'contents',
            0,
            'continuationItemRenderer',
            'continuationEndpoint',
            'continuationCommand',
            'token',
          ]);
          if (t is String) commentsToken = t;
        }
        final primary = s['videoPrimaryInfoRenderer'];
        if (primary is Map) {
          title = _text(primary['title']);
          views = _text(
              _path(primary, ['viewCount', 'videoViewCountRenderer', 'viewCount']));
          date = _text(primary['dateText']);
        }
        final secondary = s['videoSecondaryInfoRenderer'];
        if (secondary is Map) {
          final owner = _path(secondary, ['owner', 'videoOwnerRenderer']);
          channelName = _text(_path(owner, ['title']));
          channelId = _path(owner, [
            'navigationEndpoint',
            'browseEndpoint',
            'browseId',
          ]) as String?;
          avatar =
              _path(owner, ['thumbnail', 'thumbnails', 0, 'url']) as String?;
          subs = _text(_path(owner, ['subscriberCountText']));
          description =
              (_path(secondary, ['attributedDescription', 'content']) as String?) ??
                  _text(secondary['description']);
        }
      }
    }

    final related = <YoutubeVideo>[];
    final rel = _path(data, [
      'contents',
      'twoColumnWatchNextResults',
      'secondaryResults',
      'secondaryResults',
      'results',
    ]);
    if (rel is List) {
      for (final r in rel) {
        if (r is! Map) continue;
        final lv = r['lockupViewModel'];
        if (lv is! Map) continue; // skip ads/shelves/promos
        final v = _lockup(Map<String, dynamic>.from(lv));
        if (v != null) related.add(v);
      }
    }

    return YoutubeWatchDetails(
      id: videoId,
      title: title,
      viewsLabel: views,
      dateLabel: date,
      channelName: channelName,
      channelId: channelId,
      channelAvatarUrl: avatar,
      subscribersLabel: subs,
      description: description,
      related: related,
      commentsToken: commentsToken,
      chapters: _chapters(data),
    );
  }

  /// Top-level comments for a token from [watch].
  ///
  /// The renderers only carry keys: the actual comment bodies arrive in a
  /// separate entity store, so build that map first and look each thread up.
  Future<YtCommentsPage> comments(String token) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _nextEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {'context': _context, 'continuation': token},
    );
    final data = res.data;
    if (data == null) return const YtCommentsPage();

    final entities = _commentEntities(data);
    final comments = <YoutubeComment>[];
    var countLabel = '';
    String? next;
    final endpoints = _path(data, ['onResponseReceivedEndpoints']);
    if (endpoints is List) {
      for (final e in endpoints) {
        final items =
            _path(e, ['reloadContinuationItemsCommand', 'continuationItems']) ??
                _path(e, ['appendContinuationItemsAction', 'continuationItems']);
        if (items is! List) continue;
        for (final i in items) {
          if (i is! Map) continue;
          final header = i['commentsHeaderRenderer'];
          if (header is Map) {
            countLabel = _text(header['countText']).split(' ').first;
          }
          final thread = i['commentThreadRenderer'];
          if (thread is Map) {
            final key = _path(
                thread, ['commentViewModel', 'commentViewModel', 'commentKey']);
            final payload = (key is String) ? entities[key] : null;
            if (payload != null) {
              final c = _comment(payload, replyToken: _replyToken(thread));
              if (c != null) comments.add(c);
            }
          }
          final t = _path(i, [
            'continuationItemRenderer',
            'continuationEndpoint',
            'continuationCommand',
            'token',
          ]);
          if (t is String) next = t;
        }
      }
    }
    return YtCommentsPage(
        comments: comments, continuation: next, countLabel: countLabel);
  }

  /// Fetches one comment's reply thread, plus a token for more replies if the
  /// thread is paginated. Reuses the same `next` endpoint as top-level comments.
  Future<YtCommentsPage> commentReplies(String token) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _nextEndpoint,
      queryParameters: const {'prettyPrint': 'false'},
      data: {'context': _context, 'continuation': token},
    );
    final data = res.data;
    if (data == null) return const YtCommentsPage();

    final entities = _commentEntities(data);
    final replies = <YoutubeComment>[];
    String? next;
    final endpoints = _path(data, ['onResponseReceivedEndpoints']);
    if (endpoints is List) {
      for (final e in endpoints) {
        final items = _path(
                e, ['appendContinuationItemsAction', 'continuationItems']) ??
            _path(e, ['reloadContinuationItemsCommand', 'continuationItems']);
        if (items is! List) continue;
        for (final i in items) {
          if (i is! Map) continue;
          // Reply items are commentViewModel with the key one level deep.
          final key = _path(i, ['commentViewModel', 'commentKey']);
          final payload = (key is String) ? entities[key] : null;
          if (payload != null) {
            final c = _comment(payload, allowReplies: true);
            if (c != null) replies.add(c);
          }
          final t = _path(i, [
                'continuationItemRenderer',
                'button',
                'buttonRenderer',
                'command',
                'continuationCommand',
                'token',
              ]) ??
              _path(i, [
                'continuationItemRenderer',
                'continuationEndpoint',
                'continuationCommand',
                'token',
              ]);
          if (t is String) next = t;
        }
      }
    }
    return YtCommentsPage(comments: replies, continuation: next);
  }

  /// The comment mutation store: key -> commentEntityPayload.
  Map<String, Map<String, dynamic>> _commentEntities(
      Map<String, dynamic> data) {
    final entities = <String, Map<String, dynamic>>{};
    final mutations =
        _path(data, ['frameworkUpdates', 'entityBatchUpdate', 'mutations']);
    if (mutations is List) {
      for (final m in mutations) {
        final p = _path(m, ['payload', 'commentEntityPayload']);
        if (p is! Map) continue;
        final key = p['key'];
        if (key is String) entities[key] = Map<String, dynamic>.from(p);
      }
    }
    return entities;
  }

  /// The continuation token for a comment thread's replies, if any.
  String? _replyToken(Map thread) {
    final contents =
        _path(thread, ['replies', 'commentRepliesRenderer', 'contents']);
    if (contents is! List) return null;
    for (final ci in contents) {
      final t = _path(ci, [
            'continuationItemRenderer',
            'continuationEndpoint',
            'continuationCommand',
            'token',
          ]) ??
          _path(ci, [
            'continuationItemRenderer',
            'button',
            'buttonRenderer',
            'command',
            'continuationCommand',
            'token',
          ]);
      if (t is String) return t;
    }
    return null;
  }

  YoutubeComment? _comment(Map<String, dynamic> p,
      {String? replyToken, bool allowReplies = false}) {
    final id = _path(p, ['properties', 'commentId']) as String?;
    final text = _path(p, ['properties', 'content', 'content']) as String?;
    if (id == null || text == null) return null;
    // Replies come through the same store; only show top-level unless this is a
    // reply-thread fetch (allowReplies).
    final level = _path(p, ['properties', 'replyLevel']);
    if (!allowReplies && level is num && level != 0) return null;
    return YoutubeComment(
      id: id,
      text: text,
      publishedLabel:
          (_path(p, ['properties', 'publishedTime']) as String?) ?? '',
      author: (_path(p, ['author', 'displayName']) as String?) ?? '',
      channelId: _path(p, ['author', 'channelId']) as String?,
      avatarUrl: (_path(p, ['author', 'avatarThumbnailUrl']) as String?) ?? '',
      isCreator: _path(p, ['author', 'isCreator']) == true,
      isVerified: _path(p, ['author', 'isVerified']) == true,
      likeLabel: (_path(p, ['toolbar', 'likeCountNotliked']) as String?) ?? '',
      replyCount:
          int.tryParse('${_path(p, ['toolbar', 'replyCount']) ?? ''}') ?? 0,
      replyToken: replyToken,
    );
  }

  /// Related videos now arrive as `lockupViewModel` rather than the older
  /// compactVideoRenderer.
  YoutubeVideo? _lockup(Map<String, dynamic> lv) {
    if (lv['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
    final id = lv['contentId'] as String?;
    if (id == null || id.isEmpty) return null;
    final md = _path(lv, ['metadata', 'lockupMetadataViewModel']);
    final title = _path(md, ['title', 'content']) as String?;
    if (title == null || title.isEmpty) return null;

    // Row 0 is the channel; row 1 holds "1.2M views" and "2 weeks ago".
    var author = '';
    var viewsLabel = '';
    var published = '';
    String? channelId;
    final rows = _path(md, ['metadata', 'contentMetadataViewModel', 'metadataRows']);
    if (rows is List) {
      final lines = <List<String>>[];
      for (final row in rows) {
        final parts = _path(row, ['metadataParts']);
        if (parts is! List) continue;
        final line = [
          for (final p in parts) (_path(p, ['text', 'content']) as String?) ?? '',
        ];
        lines.add(line);
        // The channel row carries a browse link. It's present in search and
        // related lists but absent on a channel's own page (redundant there),
        // so key off the link rather than the row position.
        final linked = _path(row, [
          'metadataParts',
          0,
          'text',
          'commandRuns',
          0,
          'onTap',
          'innertubeCommand',
          'browseEndpoint',
          'browseId',
        ]) as String?;
        if (linked != null && linked.isNotEmpty && channelId == null) {
          channelId = linked;
          if (line.isNotEmpty) author = line[0].trim();
        }
      }
      // Views + published live in whichever row mentions "views": row 1 in a
      // search result (after the channel row), row 0 on a channel page.
      for (final line in lines) {
        final vi = line.indexWhere((p) => p.toLowerCase().contains('view'));
        if (vi < 0) continue;
        viewsLabel = line[vi];
        for (var i = 0; i < line.length; i++) {
          if (i != vi && line[i].trim().isNotEmpty) {
            published = line[i];
            break;
          }
        }
        break;
      }
    }

    final durLabel = _lockupDuration(lv);
    return YoutubeVideo(
      id: id,
      title: title,
      author: author,
      channelId: channelId,
      url: 'https://www.youtube.com/watch?v=$id',
      thumbnailUrl: 'https://img.youtube.com/vi/$id/mqdefault.jpg',
      duration: _parseDuration(durLabel),
      viewCount: _parseCompactViews(viewsLabel),
      uploadedLabel: published,
    );
  }

  /// The duration sits in a badge overlaid on the thumbnail.
  String _lockupDuration(Map<String, dynamic> lv) {
    final overlays = _path(lv, ['contentImage', 'thumbnailViewModel', 'overlays']);
    if (overlays is! List) return '';
    for (final o in overlays) {
      final badges = _path(o, ['thumbnailBottomOverlayViewModel', 'badges']);
      if (badges is! List) continue;
      for (final b in badges) {
        final t = _path(b, ['thumbnailBadgeViewModel', 'text']);
        if (t is String && t.contains(':')) return t;
      }
    }
    return '';
  }

  /// Parses compact view labels like "234K views" / "5.8M views" / "2,547 views".
  int? _parseCompactViews(String raw) {
    if (raw.isEmpty) return null;
    final m = RegExp(r'([\d.,]+)\s*([KMB])?', caseSensitive: false).firstMatch(raw);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (n == null) return null;
    return switch (m.group(2)?.toUpperCase()) {
      'K' => (n * 1000).round(),
      'M' => (n * 1000000).round(),
      'B' => (n * 1000000000).round(),
      _ => n.round(),
    };
  }

  YoutubeVideo? _video(Map<String, dynamic> r) {
    final id = r['videoId'] as String?;
    if (id == null || id.isEmpty) return null;

    final title = _text(r['title']);
    if (title.isEmpty) return null;

    final owner = r['ownerText'] ?? r['longBylineText'];
    final author = _text(owner);
    final channelId = _path(owner, [
      'runs',
      0,
      'navigationEndpoint',
      'browseEndpoint',
      'browseId',
    ]) as String?;

    final live = _isLive(r);
    final lengthLabel = _text(r['lengthText']);

    return YoutubeVideo(
      id: id,
      title: title,
      author: author,
      channelId: channelId,
      url: 'https://www.youtube.com/watch?v=$id',
      thumbnailUrl: 'https://img.youtube.com/vi/$id/mqdefault.jpg',
      duration: live ? null : _parseDuration(lengthLabel),
      viewCount: _parseViews(r),
      uploadedLabel: _text(r['publishedTimeText']),
    );
  }

  bool _isLive(Map<String, dynamic> r) {
    final badges = r['badges'];
    if (badges is List) {
      for (final b in badges) {
        final style = _path(b, ['metadataBadgeRenderer', 'style']);
        if (style == 'BADGE_STYLE_TYPE_LIVE_NOW') return true;
      }
    }
    // Live entries have no length; so does an occasional broken item.
    return _text(r['lengthText']).isEmpty;
  }

  int? _parseViews(Map<String, dynamic> r) {
    final raw = _text(r['viewCountText']);
    if (raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  /// InnerTube renders text as either `simpleText` or a list of `runs`.
  /// YouTube writes text three different ways depending on the renderer:
  /// {simpleText}, {runs:[{text}]}, and — in the newer viewModel formats that
  /// playlists and lockups use — {content}.
  String _text(dynamic node) {
    if (node is! Map) return '';
    final simple = node['simpleText'];
    if (simple is String) return simple;
    final content = node['content'];
    if (content is String) return content;
    final runs = node['runs'];
    if (runs is List) {
      return runs
          .map((e) => (e is Map ? e['text'] : null))
          .whereType<String>()
          .join();
    }
    return '';
  }

  /// Walks a JSON path, tolerating any missing or unexpected node.
  dynamic _path(dynamic node, List<Object> keys) {
    var cur = node;
    for (final k in keys) {
      if (k is int) {
        if (cur is! List || k >= cur.length) return null;
        cur = cur[k];
      } else {
        if (cur is! Map) return null;
        cur = cur[k];
      }
      if (cur == null) return null;
    }
    return cur;
  }

  Duration? _parseDuration(String raw) {
    if (raw.trim().isEmpty) return null;
    final nums = [for (final p in raw.trim().split(':')) int.tryParse(p)];
    if (nums.isEmpty || nums.any((n) => n == null)) return null;
    return switch (nums.length) {
      3 => Duration(hours: nums[0]!, minutes: nums[1]!, seconds: nums[2]!),
      2 => Duration(minutes: nums[0]!, seconds: nums[1]!),
      1 => Duration(seconds: nums[0]!),
      _ => null,
    };
  }
}

/// A channel's tabs, and the exact `params` each needs.
///
/// The obvious encoding — protobuf {2: "playlists"} — is silently ignored: the
/// request succeeds and returns the Home feed. The tab switch also needs field
/// 110, a small nested selector that differs per tab (3a videos, 9a01 shorts,
/// 7a streams, 42 playlists). These are the values real clients send, verified
/// against the live endpoint: with them, YouTube reports the requested tab as
/// selected and returns its content.
enum YtChannelTabKind {
  videos('Videos', 'EgZ2aWRlb3PyBgQKAjoA'),
  shorts('Shorts', 'EgZzaG9ydHPyBgUKA5oBAA%3D%3D'),
  live('Live', 'EgdzdHJlYW1z8gYECgJ6AA%3D%3D'),
  playlists('Playlists', 'EglwbGF5bGlzdHPyBgQKAkIA');

  const YtChannelTabKind(this.title, this.params);

  /// The tab's name as YouTube reports it, used to tell a real answer from a
  /// fallback to Home.
  final String title;
  final String params;
}

class YtChannelTab {
  final List<YoutubeVideo> videos;
  final List<YoutubePlaylist> playlists;

  /// Tab names this channel actually has.
  final Set<String> availableTabs;

  /// False when YouTube fell back to Home because the tab doesn't exist.
  final bool isRequestedTab;

  /// Token for the next page of this tab, or null at the end.
  final String? continuation;

  const YtChannelTab({
    this.videos = const [],
    this.playlists = const [],
    this.availableTabs = const {},
    this.isRequestedTab = false,
    this.continuation,
  });

  bool get isEmpty => videos.isEmpty && playlists.isEmpty;
}

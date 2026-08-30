import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;

import '../models/youtube_caption.dart';

/// A transient network failure (DNS / socket) during resolution. Callers retry
/// the same track rather than skip it — common when the phone's radio naps
/// between songs during background playback.
class _YtTransientError implements Exception {}

// ---- VISIONOS resolver (a faithful port of NewPipe's method) ----
//
// YouTube bot-gates androidVr/web/tv (and VISIONOS without a visitorData) for
// many videos — music especially — with "Sign in to confirm you're not a bot".
// NewPipe's extractor clears this by calling the VISIONOS InnerTube client WITH
// a valid visitorData; that returns playabilityStatus OK and direct, pot-free,
// uncipher'd stream URLs. Ports YoutubeStreamHelper.getVisionOsPlayerResponse:
// fetch a visitorData (visitor_id endpoint), then POST the VISIONOS /player.

const _visionOsUserAgent =
    'Mozilla/5.0 (Apple Vision Pro; CPU visionOS 26_6_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

Map<String, dynamic> _visionOsClient(String? visitorData) => {
      'clientName': 'VISIONOS',
      'clientVersion': '1.04',
      'clientScreen': 'WATCH',
      'platform': 'MOBILE',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'osName': 'visionOS',
      'osVersion': '26.6.0.23O770',
      'hl': 'en',
      'gl': 'US',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
      if (visitorData != null) 'visitorData': visitorData,
    };

final Dio _ytDio = Dio(BaseOptions(
  responseType: ResponseType.json,
  headers: const {
    'Content-Type': 'application/json',
    'X-Goog-Api-Format-Version': '2',
    'User-Agent': _visionOsUserAgent,
  },
  validateStatus: (_) => true,
));

String? _cachedVisitorData;

/// Fetches (and caches) a visitorData from the InnerTube visitor_id endpoint
/// with the VISIONOS client, matching NewPipe's getVisitorDataFromInnertube.
/// Without it, VISIONOS player responses come back bot-gated.
Future<String?> _visionOsVisitorData() async {
  if (_cachedVisitorData != null) return _cachedVisitorData;
  try {
    final resp = await _ytDio.post<Map<String, dynamic>>(
      'https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false',
      data: {
        'context': {'client': _visionOsClient(null)},
      },
    );
    final rc = resp.data?['responseContext'];
    final v = rc is Map ? rc['visitorData'] : null;
    if (v is String && v.isNotEmpty) {
      _cachedVisitorData = v;
      debugPrint('[yt] visionOS visitorData ok (${v.length})');
      return v;
    }
    debugPrint('[yt] visionOS visitorData missing');
  } catch (e) {
    debugPrint('[yt] visionOS visitorData failed: $e');
  }
  return null;
}

/// Resolves streams via the VISIONOS client + visitorData. Null if unavailable
/// or gated, so the caller can fall back to youtube_explode's clients.
Future<YtStreams?> resolveVisionOs(String videoId) async {
  final visitor = await _visionOsVisitorData();
  if (visitor == null) return null;
  final sw = Stopwatch()..start();
  try {
    final resp = await _ytDio.post<Map<String, dynamic>>(
      'https://youtubei.googleapis.com/youtubei/v1/player'
      '?prettyPrint=false&id=$videoId',
      data: {
        'context': {'client': _visionOsClient(visitor)},
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
    );
    final data = resp.data;
    if (data == null) return null;
    final ps = data['playabilityStatus'];
    final status = ps is Map ? ps['status'] : null;
    if (status != 'OK') {
      debugPrint('[yt] visionOS $videoId status=$status');
      return null;
    }
    final sd = data['streamingData'];
    if (sd is! Map) return null;

    // Currently-live streams: iOS-family clients return an HLS manifest. Serve
    // that (the player opens it at the live edge) rather than parsing live
    // segments as a VOD, which yields an unplayable result and broke live
    // playback. Null when there's no HLS, so resolveYoutubeStreams' live-manifest
    // hedge can take over.
    if (_isLiveNow(data)) {
      final master = sd['hlsManifestUrl'];
      if (master is String && master.isNotEmpty) {
        // Handing mpv the HLS MASTER playlist makes ffmpeg spend ~20s before the
        // first frame; a single variant media playlist starts in a few seconds
        // (like NewPipe). Pick the best variant from the master and use that.
        final variant = await _hlsVariantUrl(master);
        debugPrint('[yt] visionOS live in ${sw.elapsedMilliseconds}ms '
            '(${variant != null ? "variant" : "master"})');
        return YtStreams(muxedUrl: variant ?? master, isLive: true);
      }
      return null;
    }

    final streams = _buildStreamsFromJson(sd.cast<String, dynamic>());
    if (streams != null) {
      debugPrint('[yt] visionOS resolved in ${sw.elapsedMilliseconds}ms');
    }
    return streams;
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      throw _YtTransientError(); // let the caller retry, don't skip the track
    }
    debugPrint('[yt] visionOS resolve failed: $e');
    return null;
  } catch (e) {
    debugPrint('[yt] visionOS resolve failed: $e');
    return null;
  }
}

/// YouTube's live HLS manifest is a master playlist; handing ffmpeg the master
/// costs ~20s before the first frame, while a single variant media playlist
/// starts in a few seconds. Fetches the master and returns the highest-
/// resolution variant's URL, or null on failure (caller falls back to master).
Future<String?> _hlsVariantUrl(String masterUrl) async {
  try {
    final resp = await _ytDio.get<String>(masterUrl,
        options: Options(responseType: ResponseType.plain));
    final lines = (resp.data ?? '').split('\n');
    String? bestUrl;
    var bestHeight = -1;
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final m = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i]);
      final h = m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
      final url = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
      if (url.startsWith('http') && h > bestHeight) {
        bestHeight = h;
        bestUrl = url;
      }
    }
    return bestUrl;
  } catch (e) {
    debugPrint('[yt] HLS variant pick failed: $e');
    return null;
  }
}

/// True when the /player response is a currently-live broadcast, which needs an
/// HLS manifest rather than VOD adaptive formats.
bool _isLiveNow(Map<String, dynamic> data) {
  final vd = data['videoDetails'];
  if (vd is Map && (vd['isLive'] == true || vd['isLiveNow'] == true)) return true;
  final mf = data['microformat'];
  final pmf = mf is Map ? mf['playerMicroformatRenderer'] : null;
  final lbd = pmf is Map ? pmf['liveBroadcastDetails'] : null;
  return lbd is Map && lbd['isLiveNow'] == true;
}

/// Builds [YtStreams] from a raw InnerTube `streamingData` object (VISIONOS
/// returns direct, uncipher'd URLs, so no signature/n solving is needed).
YtStreams? _buildStreamsFromJson(Map<String, dynamic> sd) {
  final adaptive = (sd['adaptiveFormats'] as List?) ?? const [];
  final progressive = (sd['formats'] as List?) ?? const [];

  bool hasUrl(dynamic f) => f is Map && f['url'] is String;
  String mimeOf(dynamic f) => (f['mimeType'] as String?) ?? '';
  int bitrateOf(dynamic f) => (f['bitrate'] as num?)?.toInt() ?? 0;
  int heightOf(dynamic f) => (f['height'] as num?)?.toInt() ?? 0;

  final audios =
      adaptive.where((f) => hasUrl(f) && mimeOf(f).startsWith('audio/')).toList();
  final videos =
      adaptive.where((f) => hasUrl(f) && mimeOf(f).startsWith('video/')).toList();

  String? muxedUrl;
  var muxedQualities = const <YtQuality>[];
  final mux = progressive.where(hasUrl).toList();
  if (mux.isNotEmpty) {
    mux.sort((a, b) => bitrateOf(b).compareTo(bitrateOf(a)));
    muxedUrl = mux.first['url'] as String;
    muxedQualities = _dedupeByHeight([
      for (final f in mux)
        (
          label: '${heightOf(f)}p',
          url: f['url'] as String,
          bitrate: bitrateOf(f),
          height: heightOf(f),
        ),
    ]);
  }

  String? audioUrl;
  if (audios.isNotEmpty) {
    // Multi-language videos expose every dub as a separate audio track. Pick the
    // DEFAULT track (the one YouTube marks for our requested locale, hl=en), else
    // an English-labelled track, so playback doesn't default to a Hindi/Tamil dub
    // (issue #30). Falls back to all audios for single-track videos.
    Map<String, dynamic>? trackOf(dynamic f) =>
        (f is Map && f['audioTrack'] is Map)
            ? (f['audioTrack'] as Map).cast<String, dynamic>()
            : null;
    final tracked = audios.where((f) => trackOf(f) != null).toList();
    List<dynamic> pool = audios;
    if (tracked.isNotEmpty) {
      final def =
          tracked.where((f) => trackOf(f)!['audioIsDefault'] == true).toList();
      final english = tracked.where((f) {
        final t = trackOf(f)!;
        final id = (t['id'] as String?)?.toLowerCase() ?? '';
        final name = (t['displayName'] as String?)?.toLowerCase() ?? '';
        return id.startsWith('en') || name.contains('english');
      }).toList();
      pool = def.isNotEmpty ? def : (english.isNotEmpty ? english : audios);
    }
    final mp4 = pool.where((f) => mimeOf(f).contains('mp4')).toList();
    final pick = (mp4.isNotEmpty ? mp4 : pool)
      ..sort((a, b) => bitrateOf(b).compareTo(bitrateOf(a)));
    audioUrl = pick.first['url'] as String;
  }

  // One entry per resolution, highest bitrate wins.
  final byH = <int, YtQuality>{};
  for (final f in videos) {
    final h = heightOf(f);
    final q = (
      label: '${h}p',
      url: f['url'] as String,
      bitrate: bitrateOf(f),
      height: h,
    );
    final cur = byH[h];
    if (cur == null || q.bitrate > cur.bitrate) byH[h] = q;
  }
  final qualities = byH.values.toList()
    ..sort((a, b) => b.height.compareTo(a.height));

  if (audioUrl == null && muxedUrl == null && qualities.isEmpty) return null;
  return YtStreams(
    qualities: qualities.isNotEmpty ? qualities : muxedQualities,
    audioUrl: audioUrl,
    muxedUrl: muxedUrl,
    muxedQualities: muxedQualities,
  );
}

/// One selectable video quality (a YouTube stream), or the 'Auto' default.
typedef YtQuality = ({String label, String url, int bitrate, int height});

/// Resolved playback sources for a YouTube video.
///
/// Adaptive mode pairs a video-only stream with [audioUrl] as an external audio
/// track, which is the only way YouTube exposes anything above ~360p. The muxed
/// stream is self-contained and used as a safety net.
class YtStreams {
  final List<YtQuality> qualities; // adaptive options, highest first
  final String? audioUrl; // external audio for adaptive streams
  final String? muxedUrl; // self-contained fallback
  final List<YtQuality> muxedQualities;

  /// True when [muxedUrl] is a live HLS/DASH manifest (not a finite VOD). The
  /// player opens these at the live edge so start-up doesn't buffer the whole
  /// DVR backlog, and shows a LIVE control.
  final bool isLive;

  const YtStreams({
    this.qualities = const [],
    this.audioUrl,
    this.muxedUrl,
    this.muxedQualities = const [],
    this.isLive = false,
  });

  bool get isAdaptive => audioUrl != null && qualities.isNotEmpty;
}

/// The video id inside a YouTube URL, or null when it isn't one.
String? youtubeVideoId(String url) {
  try {
    return VideoId(url).value;
  } catch (_) {
    return null;
  }
}

bool isYoutubeUrl(String url) =>
    url.contains('youtube.com') || url.contains('youtu.be');

/// The best audio-only stream URL for [videoId], for background/audio-only
/// playback. Falls back to the self-contained muxed stream when the video has no
/// separate audio track. Resolved fresh each call so an expired URL is never
/// reused (YouTube stream URLs are time-limited). Null if nothing resolves.
Future<String?> resolveYoutubeAudioUrl(String videoId) async {
  // Primary: VISIONOS + visitorData (NewPipe's method) clears the bot gate and
  // returns direct, pot-free audio URLs. Retry on transient network errors so a
  // momentary DNS blip between songs (background radio nap) doesn't skip the
  // track and stall the queue — it waits for the connection to come back.
  const backoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];
  for (var attempt = 0;; attempt++) {
    try {
      final vision = await resolveVisionOs(videoId);
      final visionUrl = vision?.audioUrl ?? vision?.muxedUrl;
      if (visionUrl != null) return visionUrl;
      break; // resolved but no usable audio — fall through to the legacy clients
    } on _YtTransientError {
      if (attempt >= backoff.length) break; // give up on the primary
      debugPrint('[yt] visionOS network error; retry ${attempt + 1} in '
          '${backoff[attempt].inSeconds}s');
      await Future.delayed(backoff[attempt]);
    }
  }

  // Fallback: youtube_explode's clients for anything VISIONOS couldn't serve.
  final id = VideoId(videoId);
  final yt = YoutubeExplode();
  try {
    for (final (name, client) in <(String, YoutubeApiClient)>[
      ('androidVr', YoutubeApiClient.androidVr),
      ('ios', YoutubeApiClient.ios),
    ]) {
      final s = await _tryVod(yt, id, name, [client]);
      if (s != null) return s.audioUrl ?? s.muxedUrl;
    }
  } on RequestLimitExceededException {
    debugPrint('[yt] rate limited resolving audio for $videoId');
  } finally {
    yt.close();
  }
  debugPrint('[yt] audio unresolved for $videoId');
  return null;
}

/// Resolves the playable streams for [url].
///
/// Fast path: the primary client (ANDROID_VR, whose adaptive URLs are fetchable
/// by mpv/ffmpeg where the plain android client's 403) resolves almost every
/// normal VOD in one call. When it can't, the remaining VOD clients and the live
/// manifest are resolved CONCURRENTLY and the first to land wins, so a live
/// stream doesn't wait out the whole VOD failure chain before its manifest is
/// even tried (that sequential walk is what made live streams slow to start).
Future<YtStreams> resolveYoutubeStreams(String url, {bool live = true}) async {
  final yt = YoutubeExplode();
  final id = VideoId(url);
  final sw = Stopwatch()..start();
  try {
    var primaryDone = false;
    // VISIONOS + visitorData first (NewPipe's method): clears the bot gate,
    // pot-free, direct URLs. androidVr (now bot-gated) drops to the fallback.
    final primary = resolveVisionOs(id.value).then((s) {
      if (s != null) primaryDone = true;
      return s;
    });

    final candidates = <Future<YtStreams?>>[primary];
    // Hedge: the primary client ALWAYS fails for a live stream, and that failure
    // can take seconds. Spin the live lookup up in parallel once the primary is
    // a little slow. But skip it entirely for callers that can't be live (audio
    // Listen is always VOD music): those 3 extra requests are pure waste and a
    // big driver of YouTube's IP rate-limiting.
    if (live) {
      candidates.add(Future.delayed(const Duration(milliseconds: 600))
          .then<String?>(
              (_) => primaryDone ? null : _resolveLiveManifest(id.value))
          .then((u) => (u == null || u.isEmpty)
              ? null
              : YtStreams(muxedUrl: u, isLive: true)));
    }

    final first = await _firstNonNull<YtStreams>(candidates);
    if (first != null) {
      debugPrint('[yt] resolved in ${sw.elapsedMilliseconds}ms');
      return first;
    }

    // Neither the primary client nor the live lookup produced anything; fall
    // back to the remaining VOD clients before giving up.
    final rest = await _resolveVodRemaining(yt, id);
    if (rest != null) {
      debugPrint('[yt] resolved (fallback) in ${sw.elapsedMilliseconds}ms');
      return rest;
    }

    debugPrint('[yt] no streams found in ${sw.elapsedMilliseconds}ms ($url)');
    throw VideoUnavailableException(
        'Video "${id.value}" does not contain any playable streams.');
  } finally {
    yt.close();
  }
}

/// One getManifest attempt with a specific client set, built into [YtStreams] if
/// the result is usable, else null. Never throws.
Future<YtStreams?> _tryVod(YoutubeExplode yt, VideoId id, String name,
    List<YoutubeApiClient> clients,
    {bool requireWatchPage = true}) async {
  try {
    final m = await yt.videos.streamsClient
        .getManifest(id, ytClients: clients, requireWatchPage: requireWatchPage);
    if (m.muxed.isNotEmpty ||
        (m.videoOnly.isNotEmpty && m.audioOnly.isNotEmpty)) {
      return _buildStreams(m);
    }
    debugPrint('[yt] client "$name" returned no usable streams');
  } catch (e) {
    debugPrint('[yt] client "$name" failed: $e');
  }
  return null;
}

/// The VOD clients past the primary, plus the library default as a last resort.
Future<YtStreams?> _resolveVodRemaining(YoutubeExplode yt, VideoId id) async {
  for (final (name, clients) in <(String, List<YoutubeApiClient>)>[
    // androidVr was the old primary; keep it as a fallback for when VISIONOS
    // can't serve a given video (it's bot-gated intermittently, not always).
    ('androidVr', [YoutubeApiClient.androidVr]),
    ('ios', [YoutubeApiClient.ios]),
    // 'tv' (TVHTML5) consistently returns "No host specified in URI" in this
    // youtube_explode version — a guaranteed-failed request, so it's dropped.
    ('mweb', [YoutubeApiClient.mweb]),
  ]) {
    final s = await _tryVod(yt, id, name, clients);
    if (s != null) return s;
  }
  try {
    return _buildStreams(await yt.videos.streamsClient.getManifest(id));
  } catch (e) {
    debugPrint('[yt] default VOD clients failed: $e');
    return null;
  }
}

/// Builds [YtStreams] from a resolved manifest: an adaptive video+audio pairing
/// (the only way past ~360p) with a self-contained muxed stream as the safety
/// net, or just the muxed set when adaptive isn't available.
YtStreams _buildStreams(StreamManifest manifest) {
  String? muxedUrl;
  var muxedQualities = const <YtQuality>[];
  if (manifest.muxed.isNotEmpty) {
    muxedUrl = manifest.muxed.withHighestBitrate().url.toString();
    muxedQualities = _dedupeByHeight([
      for (final s in manifest.muxed)
        (
          label: '${s.videoResolution.height}p',
          url: s.url.toString(),
          bitrate: s.bitrate.bitsPerSecond,
          height: s.videoResolution.height,
        ),
    ]);
  }

  if (manifest.videoOnly.isEmpty || manifest.audioOnly.isEmpty) {
    return YtStreams(
      muxedUrl: muxedUrl,
      muxedQualities: muxedQualities,
      qualities: muxedQualities,
    );
  }

  // Best audio: prefer the DEFAULT (locale-matched) track, else an English one,
  // so multi-language videos don't default to a Hindi/Tamil dub (issue #30);
  // then prefer mp4/AAC and the highest bitrate available.
  final audios = manifest.audioOnly.toList();
  final tracked = audios.where((s) => s.audioTrack != null).toList();
  var audioPool = audios;
  if (tracked.isNotEmpty) {
    final def = tracked.where((s) => s.audioTrack!.audioIsDefault).toList();
    final english = tracked.where((s) {
      final id = s.audioTrack!.id.toLowerCase();
      final name = s.audioTrack!.displayName.toLowerCase();
      return id.startsWith('en') || name.contains('english');
    }).toList();
    audioPool = def.isNotEmpty ? def : (english.isNotEmpty ? english : audios);
  }
  final mp4Audio = audioPool.where((s) => s.container.name == 'mp4').toList();
  final audioPick = (mp4Audio.isNotEmpty ? mp4Audio : audioPool)
    ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

  // One entry per resolution, choosing the codec that decodes cheapest in
  // software: H.264 (mp4) up to 1080p, VP9 (webm) above it (lighter than AV1).
  bool preferMp4(int h) => h <= 1080;
  final byH = <int, YtQuality>{};
  final rankH = <int, int>{};
  for (final s in manifest.videoOnly) {
    final h = s.videoResolution.height;
    final isMp4 = s.container.name == 'mp4';
    final rank = (isMp4 == preferMp4(h)) ? 0 : 1;
    final q = (
      label: '${h}p',
      url: s.url.toString(),
      bitrate: s.bitrate.bitsPerSecond,
      height: h,
    );
    final curRank = rankH[h];
    if (curRank == null ||
        rank < curRank ||
        (rank == curRank && q.bitrate > byH[h]!.bitrate)) {
      byH[h] = q;
      rankH[h] = rank;
    }
  }

  return YtStreams(
    qualities: byH.values.toList()
      ..sort((a, b) => b.height.compareTo(a.height)),
    audioUrl: audioPick.first.url.toString(),
    muxedUrl: muxedUrl,
    muxedQualities: muxedQualities,
  );
}

/// Completes with the first future that yields a non-null value, or null once
/// every future has completed null (or errored). Errors are swallowed.
Future<T?> _firstNonNull<T>(List<Future<T?>> futures) {
  final completer = Completer<T?>();
  var remaining = futures.length;
  if (remaining == 0) return Future.value(null);
  void settle(T? v) {
    if (completer.isCompleted) return;
    if (v != null) {
      completer.complete(v);
    } else if (--remaining == 0) {
      completer.complete(null);
    }
  }

  for (final f in futures) {
    f.then(settle).catchError((_) {
      if (!completer.isCompleted && --remaining == 0) completer.complete(null);
    });
  }
  return completer.future;
}

/// Fetches a live stream's manifest URL straight from the InnerTube /player
/// endpoint, trying the clients that still return one (the browser/WEB client
/// went manifestless SABR). Prefers HLS (mpv handles it best), falls back to
/// DASH. Returns null when no client yields a manifest (i.e. not actually live,
/// or fully gated). This is the piece youtube_explode 3.1.0 doesn't do for us.
Future<String?> _resolveLiveManifest(String videoId) async {
  final dio = Dio(BaseOptions(
    responseType: ResponseType.json,
    // A gated/odd response is handled by reading streamingData, not the status.
    validateStatus: (_) => true,
  ));
  // iOS and TV client responses carry live manifests without a po_token; the
  // sdk-less android client is a further fallback. All three are asked at once
  // and the first to return a manifest wins, so this costs one round-trip, not
  // three, which is what keeps live start-up snappy.
  final clients = <(String, YoutubeApiClient)>[
    ('IOS', YoutubeApiClient.ios),
    ('TVHTML5', YoutubeApiClient.tv),
    ('ANDROID', YoutubeApiClient.androidSdkless),
  ];
  try {
    return await _firstNonNull<String>([
      for (final (name, c) in clients) _liveManifestFrom(dio, name, c, videoId),
    ]);
  } finally {
    dio.close(force: true);
  }
}

Future<String?> _liveManifestFrom(
    Dio dio, String name, YoutubeApiClient c, String videoId) async {
  try {
    final ua = c.payload['context']?['client']?['userAgent'] as String?;
    final res = await dio.post<dynamic>(
      c.apiUrl,
      data: {
        ...c.payload,
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'User-Agent': ?ua,
        ...c.headers,
      }),
    );
    final body = res.data;
    final data = body is Map ? body : null;
    final sd = data?['streamingData'] as Map?;
    final hls = sd?['hlsManifestUrl'] as String?;
    final dash = sd?['dashManifestUrl'] as String?;
    // HLS is what mpv plays most reliably here (DASH opened even slower and then
    // stalled). DASH is only a last resort if there's no HLS.
    final useHls = hls != null && hls.isNotEmpty;
    final url = useHls ? hls : (dash != null && dash.isNotEmpty ? dash : null);
    if (url != null) {
      debugPrint('[yt] live manifest via $name (${useHls ? 'HLS' : 'DASH'})');
      debugPrint('[yt] manifest url: $url');
      return url;
    }
    debugPrint('[yt] $name returned no live manifest');
  } catch (e) {
    debugPrint('[yt] live manifest client $name failed: $e');
  }
  return null;
}

/// The default target for a quality preference. 'auto' caps at 1080p (smooth
/// under software decoding); an explicit height picks the best option at or
/// below it. [qualities] must be sorted high-to-low.
YtQuality? defaultQualityFor(List<YtQuality> qualities, String pref) {
  if (qualities.isEmpty) return null;
  final cap = pref == 'auto' ? 1080 : (int.tryParse(pref) ?? 1080);
  for (final q in qualities) {
    if (q.height <= cap) return q;
  }
  return qualities.last; // everything is above the cap; take the smallest
}

/// Ceiling for the automatic quality pick. 4K/1440p are left to an explicit
/// choice: auto-selecting them is aggressive on bandwidth and brutal under the
/// software decoding this build falls back to.
const _autoQualityCeiling = 1080;

int? _cachedBps;
final _bwCacheAge = Stopwatch();

/// Estimates downstream throughput (bits/sec) by timing the opening bytes of
/// [url] (YouTube bursts the first chunk at full speed, so a short read is a
/// fair sample). Bounded to ~2s so it can't stall start-up, and cached briefly
/// so hopping between videos doesn't re-probe every time. Null when unmeasurable.
Future<int?> estimateBandwidthBps(String url) async {
  if (url.isEmpty) return null;
  if (_cachedBps != null &&
      _bwCacheAge.isRunning &&
      _bwCacheAge.elapsed < const Duration(seconds: 120)) {
    return _cachedBps;
  }
  final dio = Dio();
  try {
    final sw = Stopwatch()..start();
    final res = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-${4 * 1024 * 1024 - 1}'},
      ),
    );
    var bytes = 0;
    const target = 1024 * 1024; // stop after ~1 MiB...
    const budgetMs = 1000; // ...or 1 second, whichever first.
    // A link that has already delivered a small burst faster than the 1080p
    // ceiling needs (~8 Mbit/s, i.e. the top rate plus audio and safety margin)
    // won't be the thing that caps quality, so there's nothing to learn by
    // reading further: bail the moment that's clear. On a fast connection this
    // ends the probe in a few hundred ms instead of the full budget, which is
    // pure start-up latency saved before the first frame.
    const fastEnoughBps = 8000000;
    await for (final chunk in res.data!.stream) {
      bytes += chunk.length;
      final ms = sw.elapsedMilliseconds;
      if (bytes >= 256 * 1024 && ms >= 80 && bytes * 8 * 1000 / ms >= fastEnoughBps) {
        break;
      }
      if (bytes >= target || ms >= budgetMs) break;
    }
    final ms = sw.elapsedMilliseconds;
    if (bytes < 128 * 1024 || ms < 20) return null; // too small a sample
    final bps = (bytes * 8 * 1000 / ms).round();
    _cachedBps = bps;
    _bwCacheAge
      ..reset()
      ..start();
    return bps;
  } catch (_) {
    return null;
  } finally {
    dio.close(force: true);
  }
}

/// The bandwidth-aware pick for the 'auto' preference: the highest rendition (up
/// to [_autoQualityCeiling]) the measured connection can sustain with headroom.
/// Falls back to the ceiling when bandwidth can't be measured. [probeUrl] should
/// be a real stream URL (the audio track is ideal — small and always present).
Future<YtQuality?> autoQualityByBandwidth(
    List<YtQuality> qualities, String probeUrl) async {
  if (qualities.isEmpty) return null;
  final pool = qualities.where((q) => q.height <= _autoQualityCeiling).toList();
  final capped = pool.isEmpty ? qualities : pool; // everything above the ceiling
  final bps = await estimateBandwidthBps(probeUrl);
  if (bps == null) return capped.first; // unmeasurable: best within the ceiling
  const audioBps = 160000; // adaptive plays a separate audio track too
  const safety = 1.5; // headroom so playback doesn't immediately stall
  for (final q in capped) {
    // capped is sorted high -> low
    if ((q.bitrate + audioBps) * safety <= bps) return q;
  }
  return capped.last; // even the lowest exceeds the measured link
}

List<YtQuality> _dedupeByHeight(List<YtQuality> list) {
  final byH = <int, YtQuality>{};
  for (final q in list) {
    final ex = byH[q.height];
    if (ex == null || q.bitrate > ex.bitrate) byH[q.height] = q;
  }
  return byH.values.toList()..sort((a, b) => b.height.compareTo(a.height));
}

/// Subtitle tracks for [videoId], as WebVTT.
///
/// YouTube lists every language once per format (srv1/srv2/srv3/ttml/vtt), so a
/// video with six languages arrives as ~30 tracks. They're deduped by language
/// here, preferring authored captions over auto-generated ones.
///
/// The URLs are rewritten with fmt=vtt: the default response is YouTube's own
/// XML, which mpv cannot parse. Verified against the live endpoint — fmt=vtt
/// returns a real WEBVTT document.
Future<List<YoutubeCaption>> resolveYoutubeCaptions(String videoId) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.closedCaptions.getManifest(videoId);
    final byLanguage = <String, YoutubeCaption>{};

    for (final track in manifest.tracks) {
      final code = track.language.code;
      final existing = byLanguage[code];
      // First one wins, except that an authored track displaces an auto one.
      if (existing != null &&
          !(existing.isAutoGenerated && !track.isAutoGenerated)) {
        continue;
      }
      final url = track.url.replace(queryParameters: {
        ...track.url.queryParameters,
        'fmt': 'vtt',
      });
      byLanguage[code] = YoutubeCaption(
        code: code,
        label: track.language.name,
        vttUrl: url.toString(),
        isAutoGenerated: track.isAutoGenerated,
      );
    }

    final out = byLanguage.values.toList()
      ..sort((a, b) {
        // Authored before auto-generated, then alphabetical.
        if (a.isAutoGenerated != b.isAutoGenerated) {
          return a.isAutoGenerated ? 1 : -1;
        }
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return out;
  } catch (_) {
    // No captions is normal; never let it break playback.
    return const [];
  } finally {
    yt.close();
  }
}

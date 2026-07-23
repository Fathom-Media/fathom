import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';
import '../routing/app_router.dart';
import 'providers.dart';
import 'session_controller.dart';
import 'syncplay.dart';

/// A SyncPlay playback command to apply to the local player, emitted at the
/// scheduled moment (the server's `When`, converted to local time via the
/// measured clock offset) so members line up rather than reacting on arrival.
class SyncCommand {
  final String command; // Unpause | Pause | Seek | Stop
  final Duration position;
  final int seq; // increments so the player reacts to each command
  const SyncCommand(this.command, this.position, this.seq);
}

class SyncCommandNotifier extends Notifier<SyncCommand?> {
  @override
  SyncCommand? build() => null;
  void set(SyncCommand c) => state = c;
}

/// The latest SyncPlay command; the player watches this and applies it.
final syncCommandProvider =
    NotifierProvider<SyncCommandNotifier, SyncCommand?>(SyncCommandNotifier.new);

class GroupStateNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? s) => state = s;
}

/// The group's playback state (Idle | Waiting | Paused | Playing), from the
/// server's StateUpdate. The player watches this to seek to a pending resume
/// point once the whole group is actually Playing.
final groupStateProvider =
    NotifierProvider<GroupStateNotifier, String?>(GroupStateNotifier.new);

/// Full SyncPlay peer over Jellyfin's server-coordinated group API + WebSocket:
/// keeps a server clock offset, schedules incoming commands at their `When`,
/// tracks the shared queue, reports buffering/ready, drives the group with this
/// client's own pause/unpause/seek, and follows the group to whatever it's
/// playing. Interoperates with the official web/apps and any SyncPlay client.
class SyncPlaySession {
  final Ref ref;
  WebSocket? _ws;
  int _seq = 0;
  bool _wantConnected = false;

  /// serverTime - localTime; added to a local instant to get server time.
  Duration _offset = Duration.zero;
  Timer? _clockTimer;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  final List<Timer> _pending = [];

  /// The queue item the group is currently on (from a PlayQueue update), needed
  /// for Buffering/Ready reports. The server REJECTS a Ready whose PlaylistItemId
  /// doesn't match the group's current one (and keeps that member buffering), so
  /// reports must wait until this is populated from the echoed PlayQueue update.
  String? _currentPlaylistItemId;
  String? get currentPlaylistItemId => _currentPlaylistItemId;

  /// The item this client is playing locally, so a PlayQueue update for the same
  /// item doesn't bounce us into a fresh player (echo of our own SetNewQueue).
  String? _localItemId;
  String? _lastNavItemId;
  // Guards _followTo against overlapping navigations from rapid queue updates.
  bool _navigating = false;

  /// The group's current playback position, from the latest PlayQueue update.
  /// A follower opening the item seeks here so it starts where the group is,
  /// rather than at its own saved resume point.
  Duration groupStartPosition = Duration.zero;

  /// Count of live PlayerScreens (each increments on open, decrements on
  /// dispose). Used to decide whether a follow should REPLACE the current player
  /// or push a new one — the router's own location is unreliable after a
  /// non-URL-changing push, which was stacking a second player over the first.
  int _openPlayers = 0;

  /// EmittedAt of the last command we applied, to drop replays on reconnect.
  DateTime? _lastCommandAt;

  void notifyPlayerOpened() => _openPlayers++;
  void notifyPlayerClosed() {
    if (_openPlayers > 0) _openPlayers--;
  }

  SyncPlaySession(this.ref);

  void setLocalItem(String? itemId) => _localItemId = itemId;

  /// True when [itemId] is the item we most recently followed the group TO — i.e.
  /// this player is opening because we're FOLLOWING the group (so it should open
  /// paused and wait for the synchronized Unpause). When false, the user is
  /// starting a new item themselves (initiating), so it should just play.
  bool isFollowOpen(String itemId) => itemId == _lastNavItemId;

  Session? get _session => ref.read(sessionControllerProvider).asData?.value;

  Future<void> connect() async {
    _wantConnected = true;
    _lastCommandAt = null;
    await _open();
    await _syncClock();
    _clockTimer?.cancel();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _syncClock());
  }

  Future<void> _open() async {
    final s = _session;
    if (s == null) return;
    final ws = _ws;
    _ws = null;
    await ws?.close();
    final deviceId = ref.read(jellyfinClientProvider).deviceId;
    final wsBase = s.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final url = '$wsBase/socket?api_key=${s.accessToken}&deviceId=$deviceId';
    try {
      final socket = await WebSocket.connect(url);
      _ws = socket;
      socket.listen(_onMessage, onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect);
    } catch (_) {
      _ws = null;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _ws = null;
    _keepAliveTimer?.cancel();
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_wantConnected) _open();
    });
  }

  DateTime _serverNow() => DateTime.now().toUtc().add(_offset);

  Future<void> _syncClock() async {
    final s = _session;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    final t0 = DateTime.now().toUtc();
    final data = await client.getUtcTime(baseUrl: s.baseUrl, token: s.accessToken);
    final t1 = DateTime.now().toUtc();
    if (data == null) return;
    final recv = DateTime.tryParse('${data['RequestReceptionTime']}')?.toUtc();
    final trans =
        DateTime.tryParse('${data['ResponseTransmissionTime']}')?.toUtc();
    if (recv == null || trans == null) return;
    final rtt = t1.difference(t0);
    unawaited(client.syncPlayPing(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        pingMs: (rtt.inMilliseconds / 2).round()));
    final serverMid = recv.add(
        Duration(microseconds: trans.difference(recv).inMicroseconds ~/ 2));
    final localMid = t0.add(Duration(microseconds: rtt.inMicroseconds ~/ 2));
    _offset = serverMid.difference(localMid);
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      switch (msg['MessageType']) {
        case 'ForceKeepAlive':
          _ws?.add(jsonEncode({'MessageType': 'KeepAlive'}));
          // The server advertises its timeout (seconds); ping it at half that.
          final timeout = (msg['Data'] as num?)?.toInt() ?? 60;
          _keepAliveTimer?.cancel();
          _keepAliveTimer = Timer.periodic(
              Duration(seconds: (timeout ~/ 2).clamp(5, 60)),
              (_) => _ws?.add(jsonEncode({'MessageType': 'KeepAlive'})));
        case 'KeepAlive':
          break;
        case 'SyncPlayCommand':
          _handleCommand(
              (msg['Data'] as Map?)?.cast<String, dynamic>() ?? const {});
        case 'SyncPlayGroupUpdate':
          _handleGroupUpdate(
              (msg['Data'] as Map?)?.cast<String, dynamic>() ?? const {});
      }
    } catch (_) {}
  }

  void _handleCommand(Map<String, dynamic> data) {
    final cmd = data['Command'] as String?;
    if (cmd == null) return;
    // Drop stale/replayed commands. On a socket reconnect the server re-sends
    // the group's current command; without this we re-apply an old seek/pause
    // (to an out-of-date position) every time and desync. EmittedAt is the
    // server's unique emit time, so anything not newer than the last we applied
    // is a duplicate/replay. (Matches jellyfin-web's syncPlayEnabledAt gate.)
    final emittedAt = DateTime.tryParse('${data['EmittedAt']}')?.toUtc();
    if (emittedAt != null) {
      if (_lastCommandAt != null && !emittedAt.isAfter(_lastCommandAt!)) {
        return; // duplicate/replay
      }
      _lastCommandAt = emittedAt;
    }
    final ticks = (data['PositionTicks'] as num?)?.toInt() ?? 0;
    final pos = Duration(microseconds: ticks ~/ 10);
    void emit() => ref
        .read(syncCommandProvider.notifier)
        .set(SyncCommand(cmd, pos, _seq++));
    final when = DateTime.tryParse('${data['When']}')?.toUtc();
    if (when == null) {
      emit();
      return;
    }
    final delay = when.subtract(_offset).difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      emit();
    } else {
      late Timer t;
      t = Timer(delay, () {
        _pending.remove(t);
        emit();
      });
      _pending.add(t);
    }
  }

  // GroupUpdateType values are sent by name (jellyfin's GroupUpdateType enum):
  // GroupJoined, GroupLeft, UserJoined, UserLeft, StateUpdate, PlayQueue,
  // NotInGroup, GroupDoesNotExist, LibraryAccessDenied.
  void _handleGroupUpdate(Map<String, dynamic> data) {
    final type = data['Type'] as String?;
    switch (type) {
      case 'GroupJoined':
        // Confirms membership (Data is a GroupInfoDto). jellyfin-web does NOT
        // navigate or start playback here — it just enables SyncPlay and waits
        // for a PlayQueue update to drive playback. So this is a no-op for us.
        break;
      case 'GroupLeft':
      case 'GroupDoesNotExist':
        // We explicitly left, or the group is gone; reflect it and tear down.
        ref.read(syncPlayControllerProvider.notifier).markExited();
      case 'NotInGroup':
        // NOT treated as an exit here. Per the server, NotInGroup is only sent
        // as an error reply to a request/leave made while the server considers
        // us groupless — which our own time-sync ping can provoke in the brief
        // window before the New/Join POST completes. Tearing down on it would
        // wipe the group the instant we connect. A real removal always arrives
        // as GroupLeft, which we do act on.
        break;
      case 'StateUpdate':
        final d = (data['Data'] as Map?)?.cast<String, dynamic>();
        ref.read(groupStateProvider.notifier).set(d?['State'] as String?);
      case 'PlayQueue':
        _handlePlayQueue(
            (data['Data'] as Map?)?.cast<String, dynamic>() ?? const {});
    }
  }

  void _handlePlayQueue(Map<String, dynamic> pq) {
    final playlist = (pq['Playlist'] as List?) ?? const [];
    // -1 (or missing) means the group has nothing loaded — an idle/empty group,
    // e.g. the one you just created. Never navigate on that; only follow when
    // the group actually points at a queue item. When it DOES have an item, we
    // open it (the player opens paused and only plays on the group's Unpause),
    // which matches the official client: joining loads the current video and
    // shows it paused, then plays in sync when the group plays.
    final index = (pq['PlayingItemIndex'] as num?)?.toInt() ?? -1;
    if (index < 0 || index >= playlist.length) {
      _currentPlaylistItemId = null;
      return;
    }
    final startTicks = (pq['StartPositionTicks'] as num?)?.toInt() ?? 0;
    groupStartPosition = Duration(microseconds: startTicks ~/ 10);
    final entry = (playlist[index] as Map).cast<String, dynamic>();
    _currentPlaylistItemId = entry['PlaylistItemId'] as String?;
    final itemId = entry['ItemId'] as String?;
    if (itemId == null || itemId.isEmpty) return;
    // Already playing it (or we just set it) — only note the id, don't reopen.
    if (itemId == _localItemId || itemId == _lastNavItemId) return;
    _lastNavItemId = itemId;
    unawaited(_followTo(itemId));
  }

  /// Open whatever the group switched to, so a member is taken to the shared
  /// content (best-effort; a failure just leaves the user where they are).
  ///
  /// Critically, this REPLACES an existing player route instead of pushing a new
  /// one: a churning group queue (autoplay-next, the owner scrubbing a playlist,
  /// or a socket reconnect replaying the queue) would otherwise stack an
  /// unbounded number of `/player` routes, each spinning up its own mpv player,
  /// and hard-freeze the app. One player route, ever.
  Future<void> _followTo(String itemId) async {
    final s = _session;
    if (s == null || _navigating) return;
    _navigating = true;
    try {
      final item = await ref.read(jellyfinClientProvider).getItem(
          baseUrl: s.baseUrl,
          userId: s.userId,
          token: s.accessToken,
          itemId: itemId);
      // Don't yank anyone into a black player for something that can't play
      // directly (a series, season, album, folder, or a live channel).
      if (item.isFolder) return;
      _localItemId = itemId;
      final router = ref.read(routerProvider);
      // Replace the current player (tearing it down, so its audio doesn't keep
      // playing underneath) when one is already open; only push for the first.
      _openPlayers > 0
          ? router.replace('/player', extra: item)
          : router.push('/player', extra: item);
    } catch (_) {
    } finally {
      _navigating = false;
    }
  }

  // --- Outgoing (this client driving the group) ---

  /// Broadcasts a new queue to the group. Returns true if it actually did so
  /// (i.e. we're INITIATING playback of a new item) vs false when skipped
  /// because we're just following the group's current item — the caller uses
  /// this to know whether it should also request the group to start playing.
  /// [queue] is the full context queue (for an episode, the series' episodes;
  /// for a movie, a single item) with [position] the index of the item we're
  /// starting on. Sending a proper multi-item queue — like the official client —
  /// is what stops jellyfin-web's queue reconciliation from crashing on a lone
  /// item and refusing to switch.
  Future<bool> setNewQueue(
      List<String> queue, int position, Duration start) async {
    final s = _session;
    if (s == null || queue.isEmpty) return false;
    final pos = position.clamp(0, queue.length - 1);
    final current = queue[pos];
    // Already the group's current item (e.g. we opened it by following the
    // group) — don't re-broadcast our own queue.
    if (current == _localItemId && _currentPlaylistItemId != null) return false;
    _localItemId = current;
    _lastNavItemId = current;
    await ref.read(jellyfinClientProvider).syncPlaySetNewQueue(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        playingQueue: queue,
        playingItemPosition: pos,
        startPositionTicks: start.inMicroseconds * 10);
    return true;
  }

  Future<void> pause() async {
    final s = _session;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .syncPlayPause(baseUrl: s.baseUrl, token: s.accessToken);
  }

  Future<void> unpause() async {
    final s = _session;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .syncPlayUnpause(baseUrl: s.baseUrl, token: s.accessToken);
  }

  Future<void> seek(Duration position) async {
    final s = _session;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).syncPlaySeek(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        positionTicks: position.inMicroseconds * 10);
  }

  Future<void> reportBuffering(Duration position, {required bool playing}) async {
    final s = _session;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).syncPlayBuffering(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          positionTicks: position.inMicroseconds * 10,
          isPlaying: playing,
          whenIso: _serverNow().toIso8601String(),
          playlistItemId: _currentPlaylistItemId,
        );
  }

  Future<void> reportReady(Duration position, {required bool playing}) async {
    final s = _session;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).syncPlayReady(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          positionTicks: position.inMicroseconds * 10,
          isPlaying: playing,
          whenIso: _serverNow().toIso8601String(),
          playlistItemId: _currentPlaylistItemId,
        );
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _clockTimer?.cancel();
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    for (final t in _pending) {
      t.cancel();
    }
    _pending.clear();
    _currentPlaylistItemId = null;
    _lastNavItemId = null;
    final ws = _ws;
    _ws = null;
    await ws?.close();
  }
}

final syncPlaySessionProvider = Provider<SyncPlaySession>((ref) {
  final s = SyncPlaySession(ref);
  ref.onDispose(s.disconnect);
  return s;
});

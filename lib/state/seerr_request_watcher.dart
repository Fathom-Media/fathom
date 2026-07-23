import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/seerr_client.dart';
import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../models/seerr_request.dart';
import 'notifications_controller.dart';
import 'preferences.dart';
import 'providers.dart';
import 'seerr_providers.dart';

/// A request's meaningful state for change-detection. Availability (media
/// downloaded) wins over the request's own approved/pending, and a declined
/// request is declined regardless.
enum _ReqState { pending, approved, declined, available }

_ReqState _stateOf(SeerrRequest r) {
  if (r.requestStatus == 3) return _ReqState.declined;
  if ((r.mediaStatus ?? 0) >= 4) return _ReqState.available; // 4 partial, 5 full
  if (r.requestStatus == 2) return _ReqState.approved;
  return _ReqState.pending;
}

/// Polls Seerr for the user's requests and fires a notification when one flips
/// to approved, declined, or available. Persists the last-seen state per request
/// so it doesn't re-notify and can catch changes that happened while closed.
class SeerrRequestWatcher {
  SeerrRequestWatcher(this.ref, this._interval) {
    _start();
  }

  final Ref ref;
  final Duration _interval;
  Timer? _timer;
  Map<int, String> _seen = {};
  final Map<int, String> _titles = {};
  bool _firstEver = false; // no prior stored state: baseline resolved silently
  // Bumped on each change to how notifications are produced so existing pending
  // requests re-evaluate once and surface freshly. v3: request notifications now
  // deep-link to the title (route '/seerr/<type>/<id>') instead of '/discover',
  // so the old bell entries are regenerated with working links.
  static const _key = 'fathom_seerr_req_states_v3';

  Future<void> _start() async {
    _seen = await _load();
    // First poll of the session: records to the in-app bell but suppresses the
    // desktop toast, so a long absence can't blast a wall of pop-ups.
    await _poll(firstRun: true);
    _firstEver = false;
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  void dispose() => _timer?.cancel();

  Future<Map<int, String>> _load() async {
    try {
      final raw = await ref.read(secureStorageProvider).read(key: _key);
      _firstEver = raw == null;
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map;
      return {
        for (final e in m.entries) int.parse('${e.key}'): '${e.value}',
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(secureStorageProvider).write(
            key: _key,
            value: jsonEncode(_seen.map((k, v) => MapEntry('$k', v))),
          );
    } catch (_) {}
  }

  Future<void> _poll({bool firstRun = false}) async {
    try {
      final client = ref.read(seerrClientProvider);
      if (client == null) return;
      final prefs =
          ref.read(preferencesProvider).asData?.value ?? const Prefs();
      if (!prefs.notifNewRequest &&
          !prefs.notifSeerrApproved &&
          !prefs.notifSeerrDeclined &&
          !prefs.notifSeerrAvailable) {
        return; // nothing to watch for
      }

      final reqs = await client.requests(take: 40, filter: 'all');
      final next = <int, String>{};
      for (final r in reqs) {
        final st = _stateOf(r);
        next[r.id] = st.name;
        final prev = _seen[r.id];
        if (prev == st.name) continue; // unchanged

        // A request new to us that's still pending surfaces as "new request"
        // (this is how existing pending requests reach the bell on the first
        // run, and how new ones arrive later). A brand-new request already in a
        // resolved state is baselined silently on the very first run, notified
        // thereafter.
        if (prev == null && st != _ReqState.pending && _firstEver) continue;

        final (enabled, kind) = switch (st) {
          _ReqState.pending => (
              prefs.notifNewRequest,
              AppNotifKind.seerrNewRequest
            ),
          _ReqState.approved => (
              prefs.notifSeerrApproved,
              AppNotifKind.seerrApproved
            ),
          _ReqState.declined => (
              prefs.notifSeerrDeclined,
              AppNotifKind.seerrDeclined
            ),
          _ReqState.available => (
              prefs.notifSeerrAvailable,
              AppNotifKind.seerrAvailable
            ),
        };
        if (!enabled) continue;

        final title = await _titleFor(client, r);
        final (label, body) = switch (kind) {
          AppNotifKind.seerrNewRequest => (
              tr.notifNewRequest,
              tr.notifPendingApproval(title)
            ),
          AppNotifKind.seerrAvailable => (
              tr.notifNowAvailable(title),
              tr.notifNowAvailableBody
            ),
          AppNotifKind.seerrApproved => (tr.notifRequestApproved, title),
          AppNotifKind.seerrDeclined => (tr.notifRequestDeclined, title),
          _ => (tr.notifRequestUpdate, title),
        };

        await pushAppNotification(ref,
            kind: kind,
            title: label,
            body: body,
            enabled: true,
            desktopToast: !firstRun,
            route: '/seerr/${r.mediaType}/${r.tmdbId}');
      }

      _seen = next; // bound growth to current request ids
      await _save();
    } catch (_) {
      // Network hiccup or the provider was torn down mid-poll: try again next tick.
    }
  }

  Future<String> _titleFor(SeerrClient client, SeerrRequest r) async {
    final cached = _titles[r.tmdbId];
    if (cached != null) return cached;
    try {
      final d = await client.detail(mediaType: r.mediaType, tmdbId: r.tmdbId);
      final t = d.title.isNotEmpty
          ? d.title
          : (r.mediaType == 'tv' ? tr.notifAShow : tr.notifAMovie);
      _titles[r.tmdbId] = t;
      return t;
    } catch (_) {
      return r.mediaType == 'tv' ? tr.notifAShow : tr.notifAMovie;
    }
  }
}

/// Live while Seerr is configured and polling is on (interval > 0); the shell
/// watches it to keep it alive. Rebuilds when the interval setting changes.
final seerrRequestWatcherProvider = Provider<SeerrRequestWatcher?>((ref) {
  final client = ref.watch(seerrClientProvider);
  final minutes = ref.watch(
      preferencesProvider.select((p) => p.asData?.value.seerrPollMinutes ?? 5));
  if (client == null || minutes <= 0) return null;
  final w = SeerrRequestWatcher(ref, Duration(minutes: minutes));
  ref.onDispose(w.dispose);
  return w;
});

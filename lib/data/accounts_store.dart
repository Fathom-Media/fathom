import 'dart:convert';

import '../models/session.dart';
import '../services/resilient_secure_storage.dart';

/// Stable per-account identity. Keys on the server id (which survives an
/// internal/external address swap) plus the user, so the active [Session.baseUrl]
/// can float between addresses without forking the account. Falls back to the
/// URL only for older sessions saved before the server id was captured.
String accountKey(Session s) => '${s.serverId ?? s.baseUrl}|${s.userId}';

/// The pre-address-switching key (URL + user), kept only to migrate a stored
/// `active` pointer to the new [accountKey] scheme on load.
String _legacyAccountKey(Session s) => '${s.baseUrl}|${s.userId}';

/// All signed-in accounts (server + user) and which one is active.
class Accounts {
  final List<Session> sessions;
  final String? activeKey;

  const Accounts({this.sessions = const [], this.activeKey});

  Session? get active {
    for (final s in sessions) {
      if (accountKey(s) == activeKey) return s;
    }
    return sessions.isNotEmpty ? sessions.first : null;
  }
}

/// Persists the account list in the OS secret store, migrating the old
/// single-session key on first read.
class AccountsStore {
  static const _key = 'fathom_accounts';
  static const _legacyKey = 'fathom_session';
  final ResilientSecureStorage _storage;

  AccountsStore(this._storage);

  Future<Accounts> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) {
      // Migrate a pre-multi-account single session, if present.
      final legacy = await _storage.read(key: _legacyKey);
      if (legacy != null) {
        try {
          final s = Session.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
          final accounts = Accounts(sessions: [s], activeKey: accountKey(s));
          await save(accounts);
          await _storage.delete(key: _legacyKey);
          return accounts;
        } catch (_) {
          await _storage.delete(key: _legacyKey);
        }
      }
      return const Accounts();
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final sessions = (data['sessions'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Session.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final activeKey = data['active'] as String?;
      // Migrate a stored `active` written under the old URL-based key scheme to
      // the stable serverId-based one, so no one gets bumped to the wrong (or
      // no) active account after the key change.
      if (activeKey != null &&
          !sessions.any((s) => accountKey(s) == activeKey)) {
        final matches =
            sessions.where((s) => _legacyAccountKey(s) == activeKey);
        if (matches.isNotEmpty) {
          final migrated = Accounts(
              sessions: sessions, activeKey: accountKey(matches.first));
          await save(migrated);
          return migrated;
        }
      }
      return Accounts(sessions: sessions, activeKey: activeKey);
    } catch (_) {
      await _storage.delete(key: _key);
      return const Accounts();
    }
  }

  Future<void> save(Accounts accounts) async {
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'sessions': accounts.sessions.map((s) => s.toJson()).toList(),
        'active': accounts.activeKey,
      }),
    );
  }
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';

String accountKey(Session s) => '${s.baseUrl}|${s.userId}';

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
  final FlutterSecureStorage _storage;

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
      return Accounts(sessions: sessions, activeKey: data['active'] as String?);
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

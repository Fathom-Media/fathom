import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts_store.dart';
import '../models/session.dart';
import 'providers.dart';

final accountsStoreProvider = Provider<AccountsStore>((ref) {
  return AccountsStore(ref.watch(secureStorageProvider));
});

/// Holds the active [Session] (or null when signed out) and manages the full
/// set of signed-in accounts (multi-server / multi-user).
class SessionController extends AsyncNotifier<Session?> {
  AccountsStore get _store => ref.read(accountsStoreProvider);
  Accounts _accounts = const Accounts();

  @override
  Future<Session?> build() async {
    _accounts = await _store.load();
    return _accounts.active;
  }

  List<Session> get accounts => _accounts.sessions;
  String? get activeKey => _accounts.activeKey;

  Future<void> signIn(Session session) async {
    final key = accountKey(session);
    final others =
        _accounts.sessions.where((s) => accountKey(s) != key).toList();
    _accounts = Accounts(sessions: [...others, session], activeKey: key);
    await _store.save(_accounts);
    state = AsyncData(session);
  }

  Future<void> switchTo(Session session) async {
    _accounts =
        Accounts(sessions: _accounts.sessions, activeKey: accountKey(session));
    await _store.save(_accounts);
    state = AsyncData(_accounts.active);
  }

  Future<void> removeAccount(Session session) async {
    final key = accountKey(session);
    final remaining =
        _accounts.sessions.where((s) => accountKey(s) != key).toList();
    final wasActive = _accounts.activeKey == key;
    _accounts = Accounts(
      sessions: remaining,
      activeKey: wasActive
          ? (remaining.isNotEmpty ? accountKey(remaining.first) : null)
          : _accounts.activeKey,
    );
    await _store.save(_accounts);
    state = AsyncData(_accounts.active);
  }

  /// Signs out the active account (switching to another if one remains).
  Future<void> signOut() async {
    final active = _accounts.active;
    if (active != null) {
      await removeAccount(active);
    } else {
      state = const AsyncData(null);
    }
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

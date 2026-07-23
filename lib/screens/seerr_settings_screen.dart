import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/seerr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/preferences.dart';

/// Configure the Seerr connection: an admin API key, or sign in with Jellyfin
/// credentials so requests are attributed to you.
class SeerrSettingsScreen extends ConsumerStatefulWidget {
  const SeerrSettingsScreen({super.key});

  @override
  ConsumerState<SeerrSettingsScreen> createState() =>
      _SeerrSettingsScreenState();
}

class _SeerrSettingsScreenState extends ConsumerState<SeerrSettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _username;
  late final TextEditingController _password;
  String _mode = 'apikey';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    _url = TextEditingController(text: p.seerrUrl);
    _key = TextEditingController(text: p.seerrApiKey);
    _username = TextEditingController();
    _password = TextEditingController();
    _mode = p.seerrAuthMode;
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final key = _key.text.trim();
    setState(() => _busy = true);
    var ok = true;
    if (url.isNotEmpty && key.isNotEmpty) {
      ok = await SeerrClient(url, key).testConnection();
    }
    await ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(
          seerrUrl: url,
          seerrApiKey: key,
          seerrAuthMode: 'apikey',
        ));
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
        content: Text(url.isEmpty
            ? l.seerrDisconnected
            : ok
                ? l.seerrConnected
                : l.seerrSavedTestFailed)));
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final user = _username.text.trim();
    final pass = _password.text;
    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      messenger.showSnackBar(SnackBar(
          content: Text(l.seerrEnterCredentials)));
      return;
    }
    setState(() => _busy = true);
    try {
      final cookie =
          await seerrJellyfinLogin(url, username: user, password: pass);
      final name = await SeerrClient(url, '', cookie: cookie).me();
      await ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(
            seerrUrl: url,
            seerrAuthMode: 'cookie',
            seerrCookie: cookie,
          ));
      if (!mounted) return;
      _password.clear();
      messenger.showSnackBar(
          SnackBar(content: Text(l.seerrSignedInAs(name ?? user))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(
        seerrAuthMode: 'apikey', seerrCookie: ''));
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.seerrSignedOut)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final signedIn = p.seerrAuthMode == 'cookie' && p.seerrCookie.isNotEmpty;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Seerr')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l.seerrIntro,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.seerrServerUrl,
              hintText: 'https://requests.example.com',
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'apikey',
                  label: Text(l.seerrApiKeySegment),
                  icon: const Icon(Icons.key_rounded)),
              ButtonSegment(
                  value: 'cookie',
                  label: Text(l.commonSignIn),
                  icon: const Icon(Icons.person_rounded)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 20),
          if (_mode == 'apikey') ...[
            TextField(
              controller: _key,
              autocorrect: false,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.seerrApiKeyLabel,
                helperText: l.seerrApiKeyHelper,
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _saveApiKey,
              child: _busy ? _spinner() : Text(l.seerrSaveTest),
            ),
          ] else ...[
            if (signedIn)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_rounded,
                      color: Colors.green),
                  title: Text(l.seerrSignedIn),
                  subtitle: Text(l.seerrRequestsAttributed),
                  trailing: TextButton(
                      onPressed: _busy ? null : _signOut,
                      child: Text(l.commonSignOut)),
                ),
              )
            else ...[
              Text(l.seerrSignInHelp,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.seerrUsernameLabel,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _busy ? null : _signIn(),
                decoration: InputDecoration(
                  labelText: l.seerrPasswordLabel,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: _busy ? _spinner() : Text(l.commonSignIn),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.5));
}

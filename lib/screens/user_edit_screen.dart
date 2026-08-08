import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/admin_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/tv_keyboard.dart';

typedef _Toggle = (String key, String label, String subtitle);

// Grouped to mirror the official dashboard's user editor. These take the
// localizations object because they carry user-facing labels but have no
// BuildContext of their own.
List<_Toggle> _managementToggles(AppLocalizations l) => <_Toggle>[
      ('IsAdministrator', l.adminAllowServerManagement,
          l.adminAllowServerManagementSub),
      ('IsDisabled', l.adminDisableUser, l.adminDisableUserSub),
      ('IsHidden', l.adminHideFromLogin, ''),
      ('EnableCollectionManagement', l.adminAllowCollectionMgmt, ''),
      ('EnableSubtitleManagement', l.adminAllowSubtitleMgmt, ''),
    ];

List<_Toggle> _playbackToggles(AppLocalizations l) => <_Toggle>[
      ('EnableMediaPlayback', l.adminAllowMediaPlayback, ''),
      ('EnableAudioPlaybackTranscoding', l.adminAllowAudioTranscoding, ''),
      ('EnableVideoPlaybackTranscoding', l.adminAllowVideoTranscoding, ''),
      ('EnablePlaybackRemuxing', l.adminAllowRemuxing, ''),
      ('EnableContentDownloading', l.adminAllowDownloads, ''),
      ('EnableContentDeletion', l.adminAllowDeleting, ''),
    ];

List<_Toggle> _liveTvToggles(AppLocalizations l) => <_Toggle>[
      ('EnableLiveTvAccess', l.adminAllowLiveTvAccess, ''),
      ('EnableLiveTvManagement', l.adminAllowLiveTvMgmt, ''),
    ];

List<_Toggle> _remoteToggles(AppLocalizations l) => <_Toggle>[
      ('EnableRemoteAccess', l.adminAllowRemoteConnections, ''),
      ('EnableRemoteControlOfOtherUsers', l.adminAllowRemoteControlOthers, ''),
      ('EnableSharedDeviceControl', l.adminAllowBeingControlled, ''),
    ];

/// Admin: view and edit a user's policy across Profile / Access / Parental /
/// Password subsections, mirroring the official dashboard.
class UserEditScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserEditScreen({super.key, required this.userId});

  @override
  ConsumerState<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends ConsumerState<UserEditScreen> {
  Map<String, dynamic> _policy = {};
  List<Map<String, dynamic>> _folders = const [];
  List<Map<String, dynamic>> _ratings = const [];
  String _name = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> get _enabledFolders =>
      ((_policy['EnabledFolders'] as List?) ?? const [])
          .map((e) => '$e')
          .toList();

  void _toggleFolder(String id, bool on) {
    final set = _enabledFolders.toSet();
    if (on) {
      set.add(id);
    } else {
      set.remove(id);
    }
    setState(() => _policy['EnabledFolders'] = set.toList());
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({dynamic session, dynamic client})? _ctx() {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return null;
    return (session: s, client: ref.read(jellyfinClientProvider));
  }

  Future<void> _load() async {
    final c = _ctx();
    if (c == null) return;
    try {
      final u = await c.client.getUser(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId);
      List<Map<String, dynamic>> folders = const [];
      List<Map<String, dynamic>> ratings = const [];
      try {
        folders = await c.client.getVirtualFolders(
            baseUrl: c.session.baseUrl, token: c.session.accessToken);
      } catch (_) {}
      try {
        ratings = await c.client.getParentalRatings(
            baseUrl: c.session.baseUrl, token: c.session.accessToken);
      } catch (_) {}
      setState(() {
        _name = u['Name'] as String? ?? '';
        _policy = Map<String, dynamic>.from((u['Policy'] as Map?) ?? {});
        _folders = folders;
        _ratings = ratings;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final c = _ctx();
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await c.client.updateUserPolicy(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId,
          policy: _policy);
      ref.invalidate(adminUsersProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.adminSaved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetPassword() async {
    final c = _ctx();
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final newPw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminSetPassword),
        content: TvTextField(
          controller: controller,
          obscure: true,
          autofocus: true,
          label: l.adminNewPasswordHint,
          hint: l.adminNewPasswordHint,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.adminSet)),
        ],
      ),
    );
    if (newPw == null) return;
    try {
      await c.client.setUserPassword(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId,
          newPassword: newPw.isEmpty ? null : newPw);
      messenger.showSnackBar(SnackBar(content: Text(l.adminPasswordUpdated)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete() async {
    final c = _ctx();
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminDeleteUser),
        content: Text(l.adminDeleteUserConfirm(_name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.client.deleteUser(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId);
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        context.pop();
        messenger.showSnackBar(SnackBar(content: Text(l.adminDeletedUser(_name))));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_name.isEmpty ? l.adminUser : _name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_name.isEmpty ? l.adminUser : _name)),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name.isEmpty ? l.adminUser : _name),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.commonSave),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l.adminTabProfile),
              Tab(text: l.adminTabAccess),
              Tab(text: l.adminTabParental),
              Tab(text: l.adminTabPassword),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _profileTab(),
            _accessTab(),
            _parentalTab(),
            _passwordTab(),
          ],
        ),
      ),
    );
  }

  // ---- tabs ----

  Widget _profileTab() {
    final l = AppLocalizations.of(context);
    return ListView(
      children: [
        _section(l.adminSectionManagement),
        for (final t in _managementToggles(l)) _toggle(t),
        _section(l.adminSectionPlayback),
        for (final t in _playbackToggles(l)) _toggle(t),
        _section(l.adminSectionLiveTv),
        for (final t in _liveTvToggles(l)) _toggle(t),
        _section(l.adminSectionRemote),
        for (final t in _remoteToggles(l)) _toggle(t),
        _section(l.adminSectionLimits),
        _intField('MaxActiveSessions', l.adminMaxSimultaneousStreams,
            hint: l.adminHintZeroUnlimited),
        _intField('LoginAttemptsBeforeLockout', l.adminFailedLoginsBeforeLockout,
            hint: l.adminFailedLoginsHint),
        _bitrateField(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _accessTab() {
    final l = AppLocalizations.of(context);
    return ListView(
      children: [
        _section(l.adminLibrariesTitle),
        SwitchListTile(
          title: Text(l.adminAccessAllLibraries),
          value: _policy['EnableAllFolders'] == true,
          onChanged: (v) => setState(() => _policy['EnableAllFolders'] = v),
        ),
        if (_policy['EnableAllFolders'] != true)
          for (final f in _folders)
            CheckboxListTile(
              dense: true,
              title: Text('${f['Name'] ?? '—'}'),
              value: _enabledFolders.contains('${f['ItemId']}'),
              onChanged: (v) => _toggleFolder('${f['ItemId']}', v ?? false),
            ),
        _section(l.adminDevicesTitle),
        SwitchListTile(
          title: Text(l.adminAccessAllDevices),
          value: _policy['EnableAllDevices'] == true,
          onChanged: (v) => setState(() => _policy['EnableAllDevices'] = v),
        ),
        _section(l.adminSectionChannels),
        SwitchListTile(
          title: Text(l.adminAccessAllChannels),
          value: _policy['EnableAllChannels'] == true,
          onChanged: (v) => setState(() => _policy['EnableAllChannels'] = v),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _parentalTab() {
    final current = (_policy['MaxParentalRating'] as num?)?.toInt();
    // Jellyfin's rating list has several names per score; dedupe by value so the
    // dropdown has exactly one item per value.
    final seen = <int>{};
    final ratings = [
      for (final r in _ratings)
        if ((r['Value'] as num?) != null &&
            seen.add((r['Value'] as num).toInt()))
          r
    ];
    final values = ratings.map((r) => (r['Value'] as num).toInt()).toSet();
    final l = AppLocalizations.of(context);
    return ListView(
      children: [
        _section(l.adminSectionMaxRating),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DropdownButtonFormField<int?>(
            initialValue: values.contains(current) ? current : null,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: l.adminMaxParentalRating,
                border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem<int?>(
                  value: null, child: Text(l.adminRatingNone)),
              for (final r in ratings)
                DropdownMenuItem<int?>(
                  value: (r['Value'] as num).toInt(),
                  child: Text('${r['Name'] ?? r['Value']}'),
                ),
            ],
            onChanged: (v) => setState(() => _policy['MaxParentalRating'] = v),
          ),
        ),
        SwitchListTile(
          title: Text(l.adminBlockUnrated),
          value: (_policy['BlockUnratedItems'] as List?)?.isNotEmpty ?? false,
          onChanged: (v) => setState(() =>
              _policy['BlockUnratedItems'] = v ? ['Other'] : <String>[]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _passwordTab() {
    final l = AppLocalizations.of(context);
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.password_rounded),
          title: Text(l.adminSetResetPassword),
          onTap: _resetPassword,
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error),
          title: Text(l.adminDeleteUser,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: _delete,
        ),
      ],
    );
  }

  // ---- shared field builders ----

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  Widget _toggle(_Toggle t) => SwitchListTile(
        title: Text(t.$2),
        subtitle: t.$3.isEmpty ? null : Text(t.$3),
        value: _policy[t.$1] == true,
        onChanged: (v) => setState(() => _policy[t.$1] = v),
      );

  Widget _intField(String key, String label, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextFormField(
          initialValue: '${(_policy[key] as num?)?.toInt() ?? 0}',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))
          ],
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) _policy[key] = n;
          },
        ),
      );

  // RemoteClientBitrateLimit is stored in bits/sec; show it in Mbps.
  Widget _bitrateField() {
    final l = AppLocalizations.of(context);
    final bps = (_policy['RemoteClientBitrateLimit'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: bps > 0 ? '${(bps / 1000000).round()}' : '0',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
            labelText: l.adminRemoteStreamingLimit,
            suffixText: 'Mbps',
            hintText: l.adminHintZeroUnlimited,
            border: const OutlineInputBorder()),
        onChanged: (v) {
          final mbps = int.tryParse(v);
          if (mbps != null) {
            _policy['RemoteClientBitrateLimit'] = mbps * 1000000;
          }
        },
      ),
    );
  }
}

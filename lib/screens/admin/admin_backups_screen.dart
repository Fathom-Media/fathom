import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/jellyfin_client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_spinner.dart';
import '../../widgets/error_view.dart';
import '../../widgets/ui_common.dart';

/// Server backups (Jellyfin 12 and newer): list, inspect, create, and restore,
/// matching what the web dashboard offers an administrator.
///
/// Backups are written to and kept on the server's own disk; the API has no
/// way to download one, so this manages them in place.
class AdminBackupsScreen extends ConsumerWidget {
  const AdminBackupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final backups = ref.watch(adminBackupsProvider);
    final supported = backups.asData?.value != null;
    return Scaffold(
      appBar: AppBar(title: Text(l.adminBackupsTitle)),
      floatingActionButton: supported
          ? FloatingActionButton.extended(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(l.adminBackupCreate),
            )
          : null,
      body: backups.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(adminBackupsProvider)),
        data: (list) {
          if (list == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.adminBackupsUnsupported,
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(l.adminBackupsHelp,
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(l.adminBackupsNone)),
                )
              else
                for (final b in list) ...[
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(_date(context, b)),
                    subtitle: Text(_includes(l, b)),
                    onTap: () => _details(context, b),
                    trailing: IconButton(
                      tooltip: l.adminBackupRestore,
                      icon: const Icon(Icons.settings_backup_restore_rounded),
                      onPressed: () => _restore(context, ref, b),
                    ),
                  ),
                  const Divider(height: 1),
                ],
            ],
          );
        },
      ),
    );
  }

  static String _date(BuildContext context, Map<String, dynamic> b) {
    final raw = '${b['DateCreated'] ?? ''}';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_jm().format(date.toLocal());
  }

  /// What a backup holds, in the order the create dialog lists them. The
  /// database is always part of one.
  static String _includes(AppLocalizations l, Map<String, dynamic> b) {
    final o = (b['Options'] as Map?) ?? const {};
    return [
      l.adminBackupDatabase,
      if (o['Metadata'] == true) l.adminBackupMetadata,
      if (o['Subtitles'] == true) l.adminBackupSubtitles,
      if (o['Trickplay'] == true) l.adminBackupTrickplay,
    ].join(', ');
  }

  void _details(BuildContext context, Map<String, dynamic> b) {
    final l = AppLocalizations.of(context);
    final path = '${b['Path'] ?? ''}';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.adminBackupDetails,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_date(ctx, b),
                  style: TextStyle(color: Theme.of(ctx).hintColor)),
              const SizedBox(height: 16),
              _field(ctx, l.adminBackupServerVersion,
                  '${b['ServerVersion'] ?? ''}'),
              _field(ctx, l.adminBackupIncludes, _includes(l, b)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _field(ctx, l.adminBackupPath, path,
                          selectable: true)),
                  IconButton(
                    tooltip: l.adminBackupPath,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: path));
                      showSnackOn(messenger, l.adminBackupPathCopied,
                          kind: SnackKind.success);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _field(BuildContext context, String label, String value,
      {bool selectable = false}) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          selectable
              ? SelectableText(value, style: style)
              : Text(value, style: style),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    // Captured now: a backup can take minutes, and this screen's ref is gone if
    // the admin leaves it meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);

    final options = await showDialog<({bool metadata, bool subtitles, bool trickplay})>(
      context: context,
      builder: (ctx) => const _CreateBackupDialog(),
    );
    if (options == null || !context.mounted) return;

    // Like the dashboard: running scheduled tasks can change data mid-backup,
    // so say which ones are running and let the admin decide.
    try {
      final tasks = await client.getScheduledTasks(
          baseUrl: s.baseUrl, token: s.accessToken);
      final running = [
        for (final t in tasks)
          if ('${t['State'] ?? 'Idle'}' != 'Idle') '- ${t['Name'] ?? ''}',
      ];
      if (running.isNotEmpty && context.mounted) {
        final go = await confirm(
          context,
          title: l.adminBackupTasksRunning,
          message: l.adminBackupTasksRunningBody(running.join('\n')),
          confirmLabel: l.adminBackupCreate,
        );
        if (!go) return;
      }
    } catch (_) {
      // Can't tell whether tasks are running; the backup can still go ahead.
    }
    if (!context.mounted) return;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l.adminBackupInProgress),
          content: Row(
            children: [
              const AppSpinner(),
              const SizedBox(width: 16),
              Expanded(child: Text(l.adminBackupDisclaimer)),
            ],
          ),
        ),
      ),
    ));
    try {
      await client.createBackup(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        metadata: options.metadata,
        subtitles: options.subtitles,
        trickplay: options.trickplay,
      );
      navigator.pop();
      showSnackOn(messenger, l.adminBackupCreated, kind: SnackKind.success);
    } catch (e) {
      navigator.pop();
      showErrorOn(messenger, e);
    }
    container.invalidate(adminBackupsProvider);
  }

  Future<void> _restore(
      BuildContext context, WidgetRef ref, Map<String, dynamic> b) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
    final path = '${b['Path'] ?? ''}';
    if (s == null || path.isEmpty) return;
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final container = ProviderScope.containerOf(context, listen: false);

    final ok = await confirm(
      context,
      title: l.adminBackupRestoreTitle,
      message: l.adminBackupRestoreBody('${b['ServerVersion'] ?? '?'}'),
      confirmLabel: l.adminBackupRestore,
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    try {
      await client.restoreBackup(
          baseUrl: s.baseUrl, token: s.accessToken, archivePath: path);
    } catch (e) {
      showErrorOn(messenger, e);
      return;
    }
    if (!context.mounted) return;

    // The server goes down to restore and comes back when it's done. Wait for
    // it the way the dashboard does, by asking until it answers again. The
    // dialog can be hidden; the restore carries on regardless.
    var waiting = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminBackupRestoring),
        content: Row(
          children: [
            const AppSpinner(),
            const SizedBox(width: 16),
            Expanded(child: Text(l.adminBackupRestoringBody)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              waiting = false;
              Navigator.pop(ctx);
            },
            child: Text(l.commonClose),
          ),
        ],
      ),
    ));
    // Give it time to actually go down first, so a server still finishing the
    // request isn't mistaken for one that has already come back.
    await Future<void>.delayed(const Duration(seconds: 30));
    while (waiting) {
      if (await client.pingServer(s.baseUrl)) {
        if (waiting) {
          waiting = false;
          navigator.pop();
          showSnackOn(messenger, l.adminBackupRestored,
              kind: SnackKind.success);
        }
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    container.invalidate(adminBackupsProvider);
  }
}

/// The Create Backup choices. The database is always part of a backup, so it
/// shows ticked and can't be changed, as in the web dashboard.
class _CreateBackupDialog extends StatefulWidget {
  const _CreateBackupDialog();

  @override
  State<_CreateBackupDialog> createState() => _CreateBackupDialogState();
}

class _CreateBackupDialogState extends State<_CreateBackupDialog> {
  bool _metadata = false;
  bool _subtitles = false;
  bool _trickplay = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.adminBackupCreate),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.adminBackupDisclaimer),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: true,
            onChanged: null,
            title: Text(l.adminBackupDatabase),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _metadata,
            onChanged: (v) => setState(() => _metadata = v ?? false),
            title: Text(l.adminBackupMetadata),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _subtitles,
            onChanged: (v) => setState(() => _subtitles = v ?? false),
            title: Text(l.adminBackupSubtitles),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _trickplay,
            onChanged: (v) => setState(() => _trickplay = v ?? false),
            title: Text(l.adminBackupTrickplay),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            metadata: _metadata,
            subtitles: _subtitles,
            trickplay: _trickplay,
          )),
          child: Text(l.adminBackupCreate),
        ),
      ],
    );
  }
}

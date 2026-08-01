import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_backup.dart';

/// Export/import of Fathom's own settings as a portable JSON file, selectable by
/// group (everything checked by default). No passwords or API keys are included.
/// Export adapts to the platform: a save dialog on desktop, the native share
/// sheet (email, Bluetooth, Files, cloud, ...) on mobile.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  Set<String>? _exportGroups; // null until initialised from what's available

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  String _groupLabel(AppLocalizations l, String group) => switch (group) {
        'appearance' => l.backupGroupAppearance,
        'player' => l.backupGroupPlayer,
        'youtube' => l.backupGroupYoutube,
        'general' => l.backupGroupGeneral,
        'radio' => l.backupGroupRadio,
        'servers' => l.backupGroupServers,
        _ => group,
      };

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(Set<String> groups) async {
    final l = AppLocalizations.of(context);
    if (groups.isEmpty) return;
    setState(() => _busy = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final map = buildSettingsExport(ref, info.version, groups);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
      const fileName = 'fathom-settings.json';

      if (_mobile) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/$fileName';
        await File(path).writeAsString(jsonStr);
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/json', name: fileName)],
          subject: l.backupExportSubject,
        );
      } else {
        final chosen = await FilePicker.platform.saveFile(
          dialogTitle: l.backupExportTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (chosen == null) return;
        final path =
            chosen.toLowerCase().endsWith('.json') ? chosen : '$chosen.json';
        await File(path).writeAsString(jsonStr);
        _snack(l.backupSavedTo(path));
      }
    } catch (e) {
      _snack(l.backupFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: l.backupImportTitle,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final content = f.bytes != null
          ? utf8.decode(f.bytes!)
          : await File(f.path!).readAsString();
      final decoded = jsonDecode(content);
      if (!isValidBackup(decoded)) throw const FormatException('invalid');
      final data = Map<String, dynamic>.from(decoded as Map);

      final present = groupsInBackup(data);
      if (present.isEmpty) throw const FormatException('empty');
      if (!mounted) return;

      final selected = await _chooseGroups(l, present, l.backupImportChoose,
          note: l.backupImportConfirmBody, action: l.backupImportAction);
      if (selected == null || selected.isEmpty) return;

      final summary = await applySettingsImport(ref, data, selected);
      if (summary.servers.isNotEmpty) {
        _snack(l.backupImportedWithServers(summary.servers.join(', ')));
      } else {
        _snack(l.backupImported);
      }
    } on FormatException {
      _snack(l.backupInvalid);
    } catch (e) {
      _snack(l.backupFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A checklist dialog over [groups] (all checked by default). Returns the
  /// chosen set, or null if cancelled.
  Future<Set<String>?> _chooseGroups(
      AppLocalizations l, Set<String> groups, String title,
      {String? note, required String action}) {
    final ordered = backupGroups.where(groups.contains).toList();
    final chosen = {...groups};
    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(note,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              for (final g in ordered)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: chosen.contains(g),
                  title: Text(_groupLabel(l, g)),
                  onChanged: (v) => setLocal(() =>
                      v == true ? chosen.add(g) : chosen.remove(g)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.commonCancel)),
            FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, chosen),
                child: Text(action)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final available = availableExportGroups(ref);
    _exportGroups ??= {...available};
    final exportGroups = _exportGroups!;
    final orderedExport = backupGroups.where(available.contains).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(l.backupIntro,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          _header(theme, _mobile ? l.backupExportSubShare : l.backupExportSub),
          for (final g in orderedExport)
            CheckboxListTile(
              value: exportGroups.contains(g),
              title: Text(_groupLabel(l, g)),
              onChanged: _busy
                  ? null
                  : (v) => setState(() =>
                      v == true ? exportGroups.add(g) : exportGroups.remove(g)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(l.backupExportTitle),
              onPressed:
                  _busy || exportGroups.isEmpty ? null : () => _export(exportGroups),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(l.backupImportTitle),
            subtitle: Text(l.backupImportSub),
            enabled: !_busy,
            onTap: _busy ? null : _import,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/diagnostics.dart';
import '../state/app_info.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';

/// App-wide troubleshooting. Turning on Diagnostic Logging records global
/// errors, app logs, and (during playback) a verbose libmpv trace into one
/// buffer the user can copy into a bug report. Lives under Settings > About
/// because it is not specific to any one feature.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.diagnosticsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l.diagnosticsIntro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.bug_report_rounded),
                  title: Text(l.prefsDiagnosticLogging),
                  subtitle: Text(l.prefsDiagnosticLoggingSub),
                  value: prefs.diagnosticLogging,
                  onChanged: (v) {
                    Diagnostics.instance.enabled = v;
                    c.edit((x) => x.copyWith(diagnosticLogging: v));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: Text(l.prefsCopyDiagnostics),
                  subtitle: Text(l.prefsCopyDiagnosticsSub),
                  onTap: () => _copy(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(l.diagnosticsClear),
                  onTap: () {
                    Diagnostics.instance.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.diagnosticsCleared)));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (Diagnostics.instance.isEmpty) {
      messenger
          .showSnackBar(SnackBar(content: Text(l.prefsDiagnosticsEmpty)));
      return;
    }
    final version = ref.read(appVersionProvider).asData?.value ?? '?';
    final session = ref.read(sessionControllerProvider).asData?.value;
    final prefs = ref.read(preferencesProvider).asData?.value;
    final report = Diagnostics.instance.report({
      'App version': version,
      'Server': session?.serverName ?? '(none)',
      'Server address': session?.baseUrl ?? '(none)',
      'Display sync': prefs?.displaySync ?? false,
      'Hardware decoding': prefs?.hardwareDecoding ?? true,
    });
    await Clipboard.setData(ClipboardData(text: report));
    messenger.showSnackBar(SnackBar(content: Text(l.prefsDiagnosticsCopied)));
  }
}

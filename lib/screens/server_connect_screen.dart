import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/server_connection.dart';
import '../state/providers.dart';
import '../widgets/app_logo.dart';
import '../widgets/error_banner.dart';

/// Step 1 of sign-in: enter a server address and validate it's a live
/// Jellyfin server before asking for credentials.
class ServerConnectScreen extends ConsumerStatefulWidget {
  const ServerConnectScreen({super.key});

  @override
  ConsumerState<ServerConnectScreen> createState() =>
      _ServerConnectScreenState();
}

class _ServerConnectScreenState extends ConsumerState<ServerConnectScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(jellyfinClientProvider);
      final baseUrl = JellyfinClient.normalizeBaseUrl(_controller.text);
      final info = await client.getPublicSystemInfo(baseUrl);
      if (!mounted) return;
      context.push(
        '/login',
        extra: ServerConnection(
          baseUrl: baseUrl,
          serverName: info.serverName,
          serverId: info.id,
          version: info.version,
        ),
      );
    } on JellyfinException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = l.appUnexpectedError('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FathomLogo(size: 64),
                const SizedBox(height: 16),
                Text('Fathom',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(l.appConnectToServer,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 36),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_loading,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: (_) => _loading ? null : _connect(),
                  decoration: InputDecoration(
                    labelText: l.appServerAddress,
                    hintText: 'jellyfin.example.com',
                    prefixIcon: const Icon(Icons.dns_rounded),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(_error!),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _connect,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(l.appConnect),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

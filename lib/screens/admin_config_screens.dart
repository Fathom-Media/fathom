import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/admin_providers.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/error_view.dart';
import '../widgets/ui_common.dart';
import '../theme/app_theme.dart';

/// Shared scaffolding for a server-config editor: loads a config map, gives the
/// subclass a mutable [draft] to bind fields to, and a Save that writes it back.
abstract class _ConfigEditorState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  Map<String, dynamic>? draft;
  bool saving = false;
  String? loadError;

  /// The localized AppBar title for this editor.
  String title(AppLocalizations l);

  /// Reads the config section to edit.
  Future<Map<String, dynamic>> load(dynamic client, dynamic session);

  /// Writes the edited config section back.
  Future<void> save(dynamic client, dynamic session, Map<String, dynamic> cfg);

  /// The editor fields, bound to [draft].
  List<Widget> fields(BuildContext context);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null) return;
    try {
      final cfg = await load(client, session);
      if (mounted) setState(() => draft = cfg);
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  Future<void> _save() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null || draft == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = AppLocalizations.of(context).adminSaved;
    setState(() => saving = true);
    try {
      await save(client, session, draft!);
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title(l))),
      body: loadError != null
          ? ErrorView(message: loadError!, onRetry: () {
              setState(() => loadError = null);
              _load();
            })
          : draft == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ...fields(context),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FilledButton.icon(
                        onPressed: saving ? null : _save,
                        icon: saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5))
                            : const Icon(Icons.save_rounded),
                        label: Text(l.commonSave),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  // ---- field builders shared by the editors ----

  Widget textField(String key, String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: '${draft![key] ?? ''}',
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => draft![key] = v,
      ),
    );
  }

  Widget intField(String key, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: '${draft![key] ?? ''}',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) draft![key] = n;
        },
      ),
    );
  }

  Widget switchField(String key, String label, {String? subtitle}) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: draft![key] == true,
      onChanged: (v) => setState(() => draft![key] = v),
    );
  }

  Widget dropdownField(
      String key, String label, Map<String, String> options) {
    final current = '${draft![key] ?? options.keys.first}';
    final value = options.containsKey(current) ? current : options.keys.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => draft![key] = v);
        },
      ),
    );
  }

  /// A comma-separated list of strings stored as a JSON array (e.g. known
  /// proxies, LAN subnets, published URIs).
  Widget strListField(String key, String label, {String? hint}) {
    final current = (draft![key] as List?)?.join(', ') ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: current,
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        onChanged: (v) {
          draft![key] = v
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        },
      ),
    );
  }

  Widget sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  // ---- variants that bind to a nested config object rather than draft ----

  Widget switchFieldIn(Map<String, dynamic> m, String key, String label,
      {String? subtitle}) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: m[key] == true,
      onChanged: (v) => setState(() => m[key] = v),
    );
  }

  Widget intFieldIn(Map<String, dynamic> m, String key, String label,
      {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: '${m[key] ?? ''}',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) m[key] = n;
        },
      ),
    );
  }

  Widget dropdownFieldIn(Map<String, dynamic> m, String key, String label,
      Map<String, String> options) {
    final current = '${m[key] ?? options.keys.first}';
    final value = options.containsKey(current) ? current : options.keys.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => m[key] = v);
        },
      ),
    );
  }

  /// A comma-separated list of ints (e.g. trickplay WidthResolutions).
  Widget intListFieldIn(Map<String, dynamic> m, String key, String label,
      {String? hint}) {
    final current = (m[key] as List?)?.join(', ') ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: current,
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        onChanged: (v) {
          final list = v
              .split(',')
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .toList();
          m[key] = list;
        },
      ),
    );
  }
}

/// General server settings: name, metadata language/country, Quick Connect.
class AdminGeneralScreen extends ConsumerStatefulWidget {
  const AdminGeneralScreen({super.key});
  @override
  ConsumerState<AdminGeneralScreen> createState() => _AdminGeneralState();
}

class _AdminGeneralState extends _ConfigEditorState<AdminGeneralScreen> {
  @override
  String title(AppLocalizations l) => l.adminGeneralTitle;

  @override
  Future<Map<String, dynamic>> load(client, session) => client
      .getServerConfiguration(baseUrl: session.baseUrl, token: session.accessToken);

  @override
  Future<void> save(client, session, cfg) async {
    await client.updateServerConfiguration(
        baseUrl: session.baseUrl, token: session.accessToken, config: cfg);
    ref.invalidate(adminServerConfigProvider);
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      sectionLabel(l.adminSectionServer),
      textField('ServerName', l.adminServerName),
      sectionLabel(l.adminSectionMetadata),
      textField('PreferredMetadataLanguage', l.adminPreferredMetadataLanguage,
          hint: l.adminMetadataLanguageHint),
      textField('MetadataCountryCode', l.adminCountry, hint: l.adminCountryHint),
      sectionLabel(l.adminSectionLibraryDisplay),
      switchField('EnableFolderView', l.adminShowFolderView,
          subtitle: l.adminShowFolderViewSubtitle),
      switchField('SaveMetadataHidden', l.adminSaveMetadataHidden),
      switchField('EnableExternalContentInSuggestions',
          l.adminExternalContentSuggestions),
      sectionLabel(l.adminSectionResume),
      intField('MinResumePct', l.adminMinResumePct),
      intField('MaxResumePct', l.adminMaxResumePct),
      intField('MinResumeDurationSeconds', l.adminMinResumeDuration),
      sectionLabel(l.adminSectionAccess),
      switchField('QuickConnectAvailable', l.adminQuickConnect,
          subtitle: l.adminQuickConnectSubtitle),
    ];
  }
}

/// Branding: the login disclaimer and custom CSS, nested under the server
/// configuration's Branding object.
class AdminBrandingScreen extends ConsumerStatefulWidget {
  const AdminBrandingScreen({super.key});
  @override
  ConsumerState<AdminBrandingScreen> createState() => _AdminBrandingState();
}

class _AdminBrandingState extends ConsumerState<AdminBrandingScreen> {
  Map<String, dynamic>? _config; // the full server config
  final _disclaimer = TextEditingController();
  final _css = TextEditingController();
  bool _splashEnabled = false;
  bool _saving = false;
  bool _busyImage = false;
  int _imgNonce = 0; // bust the splash preview cache after upload/delete
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disclaimer.dispose();
    _css.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      // Branding has its own endpoint: ServerConfiguration carries no
      // 'Branding' key, so reading it from there always came back empty and
      // showed a blank form regardless of what the server actually had set.
      final branding = await ref
          .read(jellyfinClientProvider)
          .getBrandingConfiguration(baseUrl: s.baseUrl, token: s.accessToken);
      _disclaimer.text = '${branding['LoginDisclaimer'] ?? ''}';
      _css.text = '${branding['CustomCss'] ?? ''}';
      _splashEnabled = branding['SplashscreenEnabled'] == true;
      if (mounted) setState(() => _config = branding);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _config == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = AppLocalizations.of(context).adminSaved;
    setState(() => _saving = true);
    try {
      final branding = <String, dynamic>{
        ..._config!,
        'LoginDisclaimer': _disclaimer.text,
        'CustomCss': _css.text,
        'SplashscreenEnabled': _splashEnabled,
      };
      await ref.read(jellyfinClientProvider).updateBrandingConfiguration(
          baseUrl: s.baseUrl, token: s.accessToken, branding: branding);
      _config = branding;
      ref.invalidate(adminServerConfigProvider);
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadSplash() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    final ext = (file!.extension ?? 'png').toLowerCase();
    final contentType = ext == 'jpg' || ext == 'jpeg'
        ? 'image/jpeg'
        : (ext == 'webp' ? 'image/webp' : 'image/png');
    setState(() => _busyImage = true);
    try {
      await ref.read(jellyfinClientProvider).uploadSplashscreen(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            bytes: file.bytes!,
            contentType: contentType,
          );
      if (mounted) setState(() => _imgNonce++);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busyImage = false);
    }
  }

  Future<void> _deleteSplash() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyImage = true);
    try {
      await ref.read(jellyfinClientProvider).deleteSplashscreen(
          baseUrl: s.baseUrl, token: s.accessToken);
      if (mounted) setState(() => _imgNonce++);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busyImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionControllerProvider).asData?.value;
    final headers = ref.watch(imageHeadersProvider);
    final client = ref.watch(jellyfinClientProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminBrandingTitle)),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : _config == null || s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(l.adminSplashScreen,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          '${client.splashscreenUrl(baseUrl: s.baseUrl)}?v=$_imgNonce',
                          fit: BoxFit.cover,
                          headers: headers,
                          errorBuilder: (context, _, _) => Container(
                            color:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(Icons.image_outlined,
                                size: 40,
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.adminSplashHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busyImage ? null : _uploadSplash,
                            icon: const Icon(Icons.upload_rounded),
                            label: Text(l.adminUpload),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busyImage ? null : _deleteSplash,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(l.commonDelete),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.adminEnableSplashImage),
                      value: _splashEnabled,
                      onChanged: (v) => setState(() => _splashEnabled = v),
                    ),
                    const Divider(height: 32),
                    TextField(
                      controller: _disclaimer,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: l.adminLoginDisclaimer,
                        helperText: l.adminLoginDisclaimerHelper,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _css,
                      minLines: 5,
                      maxLines: 16,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: l.adminCustomCss,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5))
                          : const Icon(Icons.save_rounded),
                      label: Text(l.commonSave),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                    ),
                  ],
                ),
    );
  }
}

/// Playback / transcoding (encoding configuration).
class AdminPlaybackScreen extends ConsumerStatefulWidget {
  const AdminPlaybackScreen({super.key});
  @override
  ConsumerState<AdminPlaybackScreen> createState() => _AdminPlaybackState();
}

class _AdminPlaybackState extends _ConfigEditorState<AdminPlaybackScreen> {
  @override
  String title(AppLocalizations l) => l.adminPlaybackTitle;

  @override
  Future<Map<String, dynamic>> load(client, session) => client.getNamedConfiguration(
      baseUrl: session.baseUrl, token: session.accessToken, key: 'encoding');

  @override
  Future<void> save(client, session, cfg) async {
    await client.updateNamedConfiguration(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        key: 'encoding',
        config: cfg);
    ref.invalidate(adminEncodingConfigProvider);
  }

  /// Ensures the nested TrickplayOptions object exists and is mutable, then
  /// returns it so the trickplay fields can bind to it.
  Map<String, dynamic> _trickplay() {
    final existing = draft!['TrickplayOptions'];
    if (existing is Map<String, dynamic>) return existing;
    final m = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    draft!['TrickplayOptions'] = m;
    return m;
  }

  /// Kicks off the server's trickplay image generation task, so enabling
  /// trickplay here actually produces the thumbnails without leaving the app.
  Future<void> _generateTrickplay() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tasks = await client.getScheduledTasks(
          baseUrl: session.baseUrl, token: session.accessToken);
      final task = tasks.firstWhere(
        (t) => '${t['Key'] ?? ''}${t['Name'] ?? ''}'
            .toLowerCase()
            .contains('trickplay'),
        orElse: () => const {},
      );
      final id = task['Id'] as String?;
      if (id == null) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.adminNoTrickplayTask)));
        return;
      }
      await client.runScheduledTask(
          baseUrl: session.baseUrl, token: session.accessToken, taskId: id);
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminGeneratingTrickplay)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = _trickplay();
    return [
      sectionLabel(l.adminSectionHardwareAccel),
      dropdownField('HardwareAccelerationType', l.adminAcceleration, {
        '': l.adminAccelNone,
        'amf': 'AMD AMF',
        'nvenc': 'Nvidia NVENC',
        'qsv': 'Intel QuickSync',
        'vaapi': 'VAAPI',
        'videotoolbox': 'Apple VideoToolbox',
        'rkmpp': 'Rockchip MPP',
        'v4l2m2m': 'V4L2 M2M',
      }),
      switchField('EnableHardwareEncoding', l.adminEnableHwEncoding),
      switchField('EnableTonemapping', l.adminEnableToneMapping),
      switchField('EnableVppTonemapping', l.adminEnableVppToneMapping),
      switchField('AllowHevcEncoding', l.adminAllowHevcEncoding),
      switchField('AllowAv1Encoding', l.adminAllowAv1Encoding),
      sectionLabel(l.adminSectionEncoding),
      dropdownField('EncoderPreset', l.adminEncoderPreset, {
        '': l.adminPresetAuto,
        'ultrafast': 'ultrafast',
        'superfast': 'superfast',
        'veryfast': 'veryfast',
        'faster': 'faster',
        'fast': 'fast',
        'medium': 'medium',
        'slow': 'slow',
        'slower': 'slower',
        'veryslow': 'veryslow',
      }),
      intField('H264Crf', l.adminH264Crf),
      intField('H265Crf', l.adminH265Crf),
      intField('EncodingThreadCount', l.adminTranscodeThreadCount),
      switchField('EnableSubtitleExtraction', l.adminEnableSubtitleExtraction),
      sectionLabel(l.adminSectionThrottling),
      switchField('EnableThrottling', l.adminThrottleTranscodes,
          subtitle: l.adminThrottleTranscodesSubtitle),
      intField('ThrottleDelaySeconds', l.adminThrottleDelay),
      sectionLabel(l.adminSectionTrickplay),
      switchFieldIn(tp, 'EnableHwAcceleration', l.adminTrickplayHwGeneration),
      switchFieldIn(tp, 'EnableHwEncoding', l.adminTrickplayHwEncoding),
      switchFieldIn(tp, 'EnableKeyFrameOnlyExtraction',
          l.adminKeyframeOnlyExtraction,
          subtitle: l.adminKeyframeOnlyExtractionSubtitle),
      dropdownFieldIn(tp, 'ScanBehavior', l.adminScanBehavior, {
        'NonBlocking': l.adminScanBehaviorNonBlocking,
        'Blocking': l.adminScanBehaviorBlocking,
      }),
      dropdownFieldIn(tp, 'ProcessPriority', l.adminProcessPriority, {
        'High': l.adminPriorityHigh,
        'AboveNormal': l.adminPriorityAboveNormal,
        'Normal': l.adminPriorityNormal,
        'BelowNormal': l.adminPriorityBelowNormal,
        'Idle': l.adminPriorityIdle,
      }),
      intFieldIn(tp, 'Interval', l.adminInterval, hint: 'e.g. 10000'),
      intListFieldIn(tp, 'WidthResolutions', l.adminWidthResolutions,
          hint: l.adminWidthResolutionsHint),
      intFieldIn(tp, 'TileWidth', l.adminTileWidth),
      intFieldIn(tp, 'TileHeight', l.adminTileHeight),
      intFieldIn(tp, 'JpegQuality', l.adminJpegQuality),
      intFieldIn(tp, 'ProcessThreads', l.adminProcessThreads),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: OutlinedButton.icon(
          onPressed: _generateTrickplay,
          icon: const Icon(Icons.movie_filter_outlined),
          label: Text(l.adminGenerateTrickplayNow),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Text(
          l.adminTrickplayGenerateHint,
          style: const TextStyle(fontSize: 12.5, color: Colors.grey),
        ),
      ),
      sectionLabel(l.adminSectionPaths),
      textField('TranscodingTempPath', l.adminTranscodingTempPath,
          hint: l.adminHintLeaveBlankDefault),
    ];
  }
}

/// Networking (network configuration).
class AdminNetworkScreen extends ConsumerStatefulWidget {
  const AdminNetworkScreen({super.key});
  @override
  ConsumerState<AdminNetworkScreen> createState() => _AdminNetworkState();
}

class _AdminNetworkState extends _ConfigEditorState<AdminNetworkScreen> {
  @override
  String title(AppLocalizations l) => l.adminNetworkingTitle;

  @override
  Future<Map<String, dynamic>> load(client, session) => client.getNamedConfiguration(
      baseUrl: session.baseUrl, token: session.accessToken, key: 'network');

  @override
  Future<void> save(client, session, cfg) async {
    await client.updateNamedConfiguration(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        key: 'network',
        config: cfg);
    ref.invalidate(adminNetworkConfigProvider);
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      sectionLabel(l.adminSectionRemoteAccess),
      switchField('EnableRemoteAccess', l.adminAllowRemoteConnections),
      textField('BaseUrl', l.adminBaseUrl, hint: 'e.g. /jellyfin'),
      sectionLabel(l.adminSectionHttps),
      switchField('EnableHttps', l.adminEnableHttps),
      switchField('RequireHttps', l.adminRequireHttps),
      textField('CertificatePath', l.adminCertificatePath,
          hint: l.adminCertificatePathHint),
      textField('CertificatePassword', l.adminCertificatePassword),
      sectionLabel(l.adminSectionPorts),
      intField('InternalHttpPort', l.adminHttpPort),
      intField('InternalHttpsPort', l.adminHttpsPort),
      intField('PublicHttpPort', l.adminPublicHttpPort),
      intField('PublicHttpsPort', l.adminPublicHttpsPort),
      sectionLabel(l.adminSectionDiscovery),
      switchField('EnableUPnP', l.adminEnableUpnp),
      switchField('AutoDiscovery', l.adminEnableAutodiscovery),
      sectionLabel(l.adminSectionAdvanced),
      switchField('EnableIPv6', l.adminEnableIpv6),
      strListField('KnownProxies', l.adminKnownProxies,
          hint: l.adminKnownProxiesHint),
      strListField('LocalNetworkSubnets', l.adminLanNetworks,
          hint: l.adminLanNetworksHint),
    ];
  }
}

/// API keys: list, create, and revoke app access tokens.
class AdminApiKeysScreen extends ConsumerWidget {
  const AdminApiKeysScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminNewApiKey),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: l.adminAppName),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.adminCreate)),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).createApiKey(
          baseUrl: s.baseUrl, token: s.accessToken, appName: ctrl.text.trim());
      ref.invalidate(adminApiKeysProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _revoke(
      BuildContext context, WidgetRef ref, String key) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminRevokeApiKeyConfirm),
        content: Text(l.adminRevokeApiKeyBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.adminRevoke)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(jellyfinClientProvider).deleteApiKey(
          baseUrl: s.baseUrl, token: s.accessToken, key: key);
      ref.invalidate(adminApiKeysProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final keys = ref.watch(adminApiKeysProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminApiKeysTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.adminNewKey),
      ),
      body: keys.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            message: '$e', onRetry: () => ref.invalidate(adminApiKeysProvider)),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.adminNoApiKeys))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final k = list[i];
                  final token = '${k['AccessToken'] ?? ''}';
                  return ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: Text('${k['AppName'] ?? '—'}'),
                    subtitle: Text(token.length > 12
                        ? '${token.substring(0, 12)}…'
                        : token),
                    trailing: IconButton(
                      tooltip: l.adminRevoke,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _revoke(context, ref, token),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Log files: pick one to view its contents.
class AdminLogsScreen extends ConsumerWidget {
  const AdminLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final logs = ref.watch(adminLogFilesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminLogsTitle)),
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(adminLogFilesProvider)),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.adminNoLogFiles))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final l = list[i];
                  final name = '${l['Name'] ?? ''}';
                  final size = (l['Size'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(name),
                    subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        context.push('/admin/logs/view', extra: name),
                  );
                },
              ),
      ),
    );
  }
}

/// Read-only viewer for a single log file.
class AdminLogViewScreen extends ConsumerStatefulWidget {
  final String name;
  const AdminLogViewScreen({super.key, required this.name});
  @override
  ConsumerState<AdminLogViewScreen> createState() => _AdminLogViewState();
}

class _AdminLogViewState extends ConsumerState<AdminLogViewScreen> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      final text = await ref.read(jellyfinClientProvider).getLogContent(
          baseUrl: s.baseUrl, token: s.accessToken, name: widget.name);
      if (mounted) setState(() => _content = text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : _content == null
              ? const Center(child: CircularProgressIndicator())
              : Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        _content!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ),
    );
  }
}

/// Plugins: installed extensions, the catalog from configured repositories, and
/// repository management.
class AdminPluginsScreen extends StatelessWidget {
  const AdminPluginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.adminPluginsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l.adminTabInstalled),
              Tab(text: l.adminTabCatalog),
              Tab(text: l.adminTabRepositories),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _InstalledPlugins(),
            _PluginCatalog(),
            _PluginRepositories(),
          ],
        ),
      ),
    );
  }
}

class _InstalledPlugins extends ConsumerWidget {
  const _InstalledPlugins();

  Future<void> _uninstall(
      BuildContext context, WidgetRef ref, String id, String name) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminUninstallConfirm(name)),
        content: Text(l.adminUninstallBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.adminUninstall)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(jellyfinClientProvider).uninstallPlugin(
          baseUrl: s.baseUrl, token: s.accessToken, pluginId: id);
      ref.invalidate(adminPluginsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminUninstalledPlugin(name))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final plugins = ref.watch(adminPluginsProvider);
    return plugins.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
          message: '$e', onRetry: () => ref.invalidate(adminPluginsProvider)),
      data: (list) => list.isEmpty
          ? Center(child: Text(l.adminNoPlugins))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminPluginsProvider),
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = list[i];
                  final id = '${p['Id'] ?? ''}';
                  final name = '${p['Name'] ?? '—'}';
                  return ListTile(
                    leading: const Icon(Icons.extension_rounded),
                    title: Text(name),
                    subtitle: Text('v${p['Version'] ?? '?'}'
                        '${p['Status'] != null ? '  ·  ${p['Status']}' : ''}'),
                    trailing: IconButton(
                      tooltip: l.adminUninstall,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: id.isEmpty
                          ? null
                          : () => _uninstall(context, ref, id, name),
                    ),
                    onTap: () =>
                        context.push('/admin/plugins/installed', extra: p),
                  );
                },
              ),
            ),
    );
  }
}

class _PluginCatalog extends ConsumerWidget {
  const _PluginCatalog();

  Future<void> _install(BuildContext context, WidgetRef ref,
      String name, String guid) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).installPackage(
          baseUrl: s.baseUrl, token: s.accessToken, name: name, guid: guid);
      ref.invalidate(adminPluginsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminInstallingPlugin(name))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final packages = ref.watch(adminPackagesProvider);
    return packages.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
          message: '$e', onRetry: () => ref.invalidate(adminPackagesProvider)),
      data: (list) => list.isEmpty
          ? Center(
              child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  l.adminNoPackages,
                  textAlign: TextAlign.center),
            ))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminPackagesProvider),
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = list[i];
                  final name = '${p['name'] ?? '—'}';
                  final guid = '${p['guid'] ?? ''}';
                  final overview = '${p['overview'] ?? p['description'] ?? ''}';
                  final imageUrl = '${p['imageUrl'] ?? ''}';
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: imageUrl.isEmpty
                          ? _pluginPlaceholder(context)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, _, _) =>
                                      _pluginPlaceholder(context)),
                            ),
                    ),
                    title: Text(name),
                    subtitle: overview.isEmpty
                        ? Text('${p['category'] ?? ''}')
                        : Text(overview,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: guid.isEmpty
                          ? null
                          : () => _install(context, ref, name, guid),
                      child: Text(l.adminInstall),
                    ),
                    onTap: () =>
                        context.push('/admin/plugins/package', extra: p),
                  );
                },
              ),
            ),
    );
  }
}

class _PluginRepositories extends ConsumerWidget {
  const _PluginRepositories();

  Future<void> _save(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> repos) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).setRepositories(
          baseUrl: s.baseUrl, token: s.accessToken, repositories: repos);
      ref.invalidate(adminRepositoriesProvider);
      ref.invalidate(adminPackagesProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> current) async {
    final l = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminAddRepository),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: l.adminName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                  labelText: l.adminManifestUrl,
                  hintText: 'https://.../manifest.json'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonAdd)),
        ],
      ),
    );
    if (ok != true || urlCtrl.text.trim().isEmpty) return;
    final next = [
      ...current,
      {
        'Name': nameCtrl.text.trim(),
        'Url': urlCtrl.text.trim(),
        'Enabled': true,
      },
    ];
    if (context.mounted) await _save(context, ref, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repos = ref.watch(adminRepositoriesProvider);
    return repos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(adminRepositoriesProvider)),
      data: (list) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(context, ref, list),
          icon: const Icon(Icons.add_rounded),
          label: Text(l.adminAddRepository),
        ),
        body: list.isEmpty
            ? Center(child: Text(l.adminNoRepositories))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = list[i];
                  return ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text('${r['Name'] ?? r['Url'] ?? '—'}'),
                    subtitle: Text('${r['Url'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: l.commonRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        final next = [...list]..removeAt(i);
                        _save(context, ref, next);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Detail for an installed plugin: art, version, status, and (for plugins that
/// expose one) a raw configuration editor, plus uninstall.
class AdminInstalledPluginScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> plugin;
  const AdminInstalledPluginScreen({super.key, required this.plugin});
  @override
  ConsumerState<AdminInstalledPluginScreen> createState() =>
      _AdminInstalledPluginState();
}

class _AdminInstalledPluginState
    extends ConsumerState<AdminInstalledPluginScreen> {
  final _json = TextEditingController();
  bool _configLoaded = false;
  bool _hasConfig = false;
  bool _saving = false;

  String get _id => '${widget.plugin['Id'] ?? ''}';
  String get _name => '${widget.plugin['Name'] ?? 'Plugin'}';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _id.isEmpty) {
      setState(() => _configLoaded = true);
      return;
    }
    try {
      final cfg = await ref.read(jellyfinClientProvider).getPluginConfiguration(
          baseUrl: s.baseUrl, token: s.accessToken, pluginId: _id);
      if (!mounted) return;
      setState(() {
        _hasConfig = cfg.isNotEmpty;
        _json.text =
            const JsonEncoder.withIndent('  ').convert(cfg);
        _configLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _configLoaded = true);
    }
  }

  Future<void> _saveConfig() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> parsed;
    try {
      parsed = Map<String, dynamic>.from(jsonDecode(_json.text) as Map);
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminInvalidJson)));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(jellyfinClientProvider).updatePluginConfiguration(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          pluginId: _id,
          config: parsed);
      messenger.showSnackBar(SnackBar(content: Text(l.adminSaved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uninstall() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminUninstallConfirm(_name)),
        content: Text(l.adminUninstallBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.adminUninstall)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(jellyfinClientProvider).uninstallPlugin(
          baseUrl: s.baseUrl, token: s.accessToken, pluginId: _id);
      ref.invalidate(adminPluginsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminUninstalledPlugin(_name))));
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionControllerProvider).asData?.value;
    final headers = ref.watch(imageHeadersProvider);
    final client = ref.watch(jellyfinClientProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: s == null || _id.isEmpty
                      ? _pluginPlaceholder(context)
                      : Image.network(
                          client.pluginImageUrl(
                              baseUrl: s.baseUrl, pluginId: _id),
                          fit: BoxFit.cover,
                          headers: headers,
                          errorBuilder: (context, _, _) =>
                              _pluginPlaceholder(context),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(l.adminPluginVersion('${widget.plugin['Version'] ?? '?'}'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    if (widget.plugin['Status'] != null)
                      Text('${widget.plugin['Status']}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if ('${widget.plugin['Description'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${widget.plugin['Description']}',
                style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          if (!_configLoaded)
            const Center(child: CircularProgressIndicator())
          else if (_hasConfig) ...[
            Text(l.adminConfigJson,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              l.adminConfigJsonHint,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _json,
              minLines: 6,
              maxLines: 24,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _saveConfig,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.save_rounded),
              label: Text(l.adminSaveConfiguration),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ] else
            Text(l.adminNoEditableConfig,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _id.isEmpty ? null : _uninstall,
            icon: Icon(Icons.delete_outline_rounded,
                color: theme.colorScheme.error),
            label: Text(l.adminUninstall,
                style: TextStyle(color: theme.colorScheme.error)),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

Widget _pluginPlaceholder(BuildContext context) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.extension_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );

/// Detail for a catalog package: art, overview, versions, and install.
class AdminPackageScreen extends ConsumerWidget {
  final Map<String, dynamic> package;
  const AdminPackageScreen({super.key, required this.package});

  Future<void> _install(BuildContext context, WidgetRef ref,
      {String? version}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).installPackage(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            name: '${package['name'] ?? ''}',
            guid: '${package['guid'] ?? ''}',
            version: version,
          );
      ref.invalidate(adminPluginsProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(l.adminInstallingPlugin('${package['name']}'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = '${package['name'] ?? 'Plugin'}';
    final imageUrl = '${package['imageUrl'] ?? ''}';
    final overview = '${package['overview'] ?? package['description'] ?? ''}';
    final versions = (package['versions'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: imageUrl.isEmpty
                      ? _pluginPlaceholder(context)
                      : Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, _) =>
                              _pluginPlaceholder(context)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    if ('${package['owner'] ?? ''}'.isNotEmpty)
                      Text(l.adminPackageBy('${package['owner']}'),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    if ('${package['category'] ?? ''}'.isNotEmpty)
                      Text('${package['category']}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _install(context, ref),
            icon: const Icon(Icons.download_rounded),
            label: Text(l.adminInstallLatest),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(overview, style: theme.textTheme.bodyMedium),
          ],
          if (versions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l.adminVersions,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final v in versions.whereType<Map>())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${v['version'] ?? '?'}'),
                subtitle: '${v['changelog'] ?? ''}'.isEmpty
                    ? null
                    : Text('${v['changelog']}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: () => _install(context, ref,
                      version: '${v['version'] ?? ''}'),
                  child: Text(l.adminInstall),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Live TV administration: tuner devices and TV guide (listing) providers.
class AdminLiveTvScreen extends ConsumerWidget {
  const AdminLiveTvScreen({super.key});

  /// Add or edit a tuner. Editing POSTs the whole existing object back with the
  /// edited fields merged in: the server upserts on Id, and anything not sent
  /// (TunerCount, UserAgent, the Allow* flags) would otherwise fall back to
  /// defaults and quietly undo the admin's setup.
  Future<void> _tunerDialog(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? existing}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final editing = existing != null;
    final urlCtrl = TextEditingController(text: '${existing?['Url'] ?? ''}');
    final nameCtrl =
        TextEditingController(text: '${existing?['FriendlyName'] ?? ''}');
    var type = '${existing?['Type'] ?? 'm3u'}';
    if (type != 'm3u' && type != 'hdhomerun') type = 'm3u';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(editing ? l.adminEditTuner : l.adminAddTuner),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: l.adminType),
                items: [
                  DropdownMenuItem(value: 'm3u', child: Text(l.adminM3uTuner)),
                  const DropdownMenuItem(
                      value: 'hdhomerun', child: Text('HDHomeRun')),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'm3u'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                    labelText: type == 'm3u' ? l.adminM3uUrl : l.adminDeviceUrl,
                    hintText:
                        type == 'hdhomerun' ? 'http://192.168.1.x' : null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: l.adminFriendlyName, hintText: l.adminHintOptional),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(editing ? l.commonSave : l.commonAdd)),
          ],
        ),
      ),
    );
    if (ok != true || urlCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).addTunerHost(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        tuner: {
          ...?existing,
          'Type': type,
          'Url': urlCtrl.text.trim(),
          if (nameCtrl.text.trim().isNotEmpty)
            'FriendlyName': nameCtrl.text.trim(),
        },
      );
      ref.invalidate(adminLiveTvInfoProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Guide providers come in two flavours, same as the official dashboard:
  /// a plain XMLTV file/URL, or a Schedules Direct account.
  Future<void> _addGuide(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.adminAddGuideProvider),
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_rounded),
            title: const Text('XMLTV'),
            subtitle: Text(l.adminXmltvSubtitle),
            onTap: () => Navigator.pop(ctx, 'xmltv'),
          ),
          ListTile(
            leading: const Icon(Icons.satellite_alt_rounded),
            title: const Text('Schedules Direct'),
            subtitle: Text(l.adminScdSubtitle),
            onTap: () => Navigator.pop(ctx, 'scd'),
          ),
        ],
      ),
    );
    if (kind == null || !context.mounted) return;
    if (kind == 'scd') {
      final added = await showDialog<bool>(
        context: context,
        builder: (_) => const _SchedulesDirectDialog(),
      );
      if (added == true) ref.invalidate(adminLiveTvInfoProvider);
      return;
    }
    if (context.mounted) await _xmltvDialog(context, ref);
  }

  /// Add or edit an XMLTV provider. As with tuners, the existing object is sent
  /// back whole so the category and channel-mapping settings survive an edit.
  Future<void> _xmltvDialog(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? existing}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final editing = existing != null;
    final ctrl = TextEditingController(text: '${existing?['Path'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing ? l.adminEditXmltvGuide : l.adminAddXmltvGuide),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
              labelText: l.adminXmltvPathLabel,
              hintText: 'https://.../guide.xml'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(editing ? l.commonSave : l.commonAdd)),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).saveListingProvider(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        info: {...?existing, 'Type': 'xmltv', 'Path': ctrl.text.trim()},
      );
      ref.invalidate(adminLiveTvInfoProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      {required String what, required Future<void> Function() onDelete}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminRemoveConfirm(what)),
        content: Text(l.adminRemoveFromServerBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonRemove)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await onDelete();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delTuner(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).deleteTunerHost(
        baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminLiveTvInfoProvider);
  }

  Future<void> _delGuide(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).deleteListingProvider(
        baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminLiveTvInfoProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final info = ref.watch(adminLiveTvInfoProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.adminLiveTvTitle),
          bottom: TabBar(tabs: [
            Tab(text: l.adminTabTuners),
            Tab(text: l.adminTabTvGuide),
            Tab(text: l.adminTabRecording),
          ]),
        ),
        body: info.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
              message: '$e',
              onRetry: () => ref.invalidate(adminLiveTvInfoProvider)),
          data: (m) {
            final tuners = (m['TunerHosts'] as List?)
                    ?.whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                const <Map<String, dynamic>>[];
            final guides = (m['ListingProviders'] as List?)
                    ?.whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                const <Map<String, dynamic>>[];
            return TabBarView(
              children: [
                _liveTvList(
                  context,
                  empty: l.adminNoTuners,
                  addLabel: l.adminAddTuner,
                  onAdd: () => _tunerDialog(context, ref),
                  items: [
                    for (final t in tuners)
                      ListTile(
                        leading: const Icon(Icons.settings_input_antenna_rounded),
                        title: Text('${t['FriendlyName'] ?? t['Url'] ?? '—'}'),
                        subtitle: Text(
                            '${_tunerType(l, t['Type'])}  ·  ${t['Url'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () =>
                            _tunerDialog(context, ref, existing: t),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: l.commonRemove,
                          onPressed: () => _confirmDelete(context, ref,
                              what: l.adminWhatTuner,
                              onDelete: () =>
                                  _delTuner(ref, '${t['Id'] ?? ''}')),
                        ),
                      ),
                  ],
                ),
                _liveTvList(
                  context,
                  empty: l.adminNoGuideProviders,
                  addLabel: l.adminAddGuideProvider,
                  onAdd: () => _addGuide(context, ref),
                  items: [
                    for (final g in guides)
                      _guideTile(context, ref, g),
                  ],
                ),
                _RecordingOptions(options: m),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _tunerType(AppLocalizations l, Object? type) =>
      switch ('$type'.toLowerCase()) {
        'm3u' => l.adminM3uTuner,
        'hdhomerun' => 'HDHomeRun',
        _ => '$type',
      };

  Widget _guideTile(
      BuildContext context, WidgetRef ref, Map<String, dynamic> g) {
    final l = AppLocalizations.of(context);
    final isScd = '${g['Type']}'.toLowerCase() == 'schedulesdirect';
    final subtitle = isScd
        ? [
            if ('${g['Username'] ?? ''}'.isNotEmpty) '${g['Username']}',
            if ('${g['ListingsId'] ?? ''}'.isNotEmpty) '${g['ListingsId']}',
          ].join('  ·  ')
        : '${g['Path'] ?? ''}';
    return ListTile(
      leading: Icon(
          isScd ? Icons.satellite_alt_rounded : Icons.menu_book_rounded),
      title: Text(isScd ? 'Schedules Direct' : 'XMLTV'),
      subtitle:
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Schedules Direct is credential-and-lineup driven, so changing it means
      // running the wizard again rather than editing fields in place.
      onTap: () async {
        if (isScd) {
          final saved = await showDialog<bool>(
            context: context,
            builder: (_) => const _SchedulesDirectDialog(),
          );
          if (saved == true) ref.invalidate(adminLiveTvInfoProvider);
        } else {
          await _xmltvDialog(context, ref, existing: g);
        }
      },
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: l.commonRemove,
        onPressed: () => _confirmDelete(context, ref,
            what: l.adminWhatGuideProvider,
            onDelete: () => _delGuide(ref, '${g['Id'] ?? ''}')),
      ),
    );
  }

  Widget _liveTvList(BuildContext context,
      {required String empty,
      required String addLabel,
      required VoidCallback onAdd,
      required List<Widget> items}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(addLabel),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(empty))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => items[i],
                ),
        ),
      ],
    );
  }
}

/// The rest of LiveTvOptions: guide depth, recording paths and padding. These
/// come from the same config section the tuners do, so they're editable here
/// rather than being read-only text.
class _RecordingOptions extends ConsumerStatefulWidget {
  final Map<String, dynamic> options;
  const _RecordingOptions({required this.options});

  @override
  ConsumerState<_RecordingOptions> createState() => _RecordingOptionsState();
}

class _RecordingOptionsState extends ConsumerState<_RecordingOptions> {
  late final Map<String, dynamic> _draft =
      Map<String, dynamic>.from(widget.options);
  bool _saving = false;

  Future<void> _save() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = AppLocalizations.of(context).adminSaved;
    setState(() => _saving = true);
    try {
      // The whole section goes back, so tuners and guide providers held in the
      // same object aren't dropped by saving a padding value.
      await ref.read(jellyfinClientProvider).updateNamedConfiguration(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          key: 'livetv',
          config: _draft);
      ref.invalidate(adminLiveTvInfoProvider);
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Outlined, matching every other admin editor. These were the one form still
  // using the default underline input, which read as a less-finished screen.
  Widget _num(String label, String key, {String? helper}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextFormField(
          initialValue: '${_draft[key] ?? ''}',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              border: const OutlineInputBorder()),
          onChanged: (v) => _draft[key] = int.tryParse(v) ?? _draft[key],
        ),
      );

  Widget _text(String label, String key, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextFormField(
          initialValue: '${_draft[key] ?? ''}',
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
          onChanged: (v) => _draft[key] = v.trim().isEmpty ? null : v.trim(),
        ),
      );

  Widget _toggle(String label, String key) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(label),
        value: _draft[key] == true,
        onChanged: (v) => setState(() => _draft[key] = v),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        SettingsSectionHeader(l.adminSectionGuide, first: true),
        _num(l.adminGuideDays, 'GuideDays',
            helper: l.adminGuideDaysHelper),
        SettingsSectionHeader(l.adminSectionRecordingPaths),
        _text(l.adminRecordingPath, 'RecordingPath'),
        _text(l.adminMovieRecordingPath, 'MovieRecordingPath'),
        _text(l.adminSeriesRecordingPath, 'SeriesRecordingPath'),
        SettingsSectionHeader(l.adminSectionPadding),
        _num(l.adminPrePadding, 'PrePaddingSeconds'),
        _num(l.adminPostPadding, 'PostPaddingSeconds'),
        SettingsSectionHeader(l.adminSectionOptions),
        _toggle(l.adminRecordingSubfolders, 'EnableRecordingSubfolders'),
        _toggle(l.adminSaveRecordingNfo, 'SaveRecordingNFO'),
        _toggle(l.adminSaveRecordingImages, 'SaveRecordingImages'),
        const SizedBox(height: 24),
        // The full-width Save the other config editors use, not a bare button.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(l.commonSave),
          ),
        ),
      ],
    );
  }
}

/// DVR: scheduled recordings, series rules, and completed recordings.
class AdminDvrScreen extends ConsumerWidget {
  const AdminDvrScreen({super.key});

  Future<void> _cancelTimer(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .cancelTimer(baseUrl: s.baseUrl, token: s.accessToken, timerId: id);
    ref.invalidate(adminTimersProvider);
  }

  Future<void> _cancelSeries(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .cancelSeriesTimer(baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminSeriesTimersProvider);
  }

  Future<void> _deleteRecording(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .deleteRecording(baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminRecordingsProvider);
  }

  Future<void> _editSeriesPadding(
      BuildContext context, WidgetRef ref, Map<String, dynamic> timer) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pre = TextEditingController(
        text: '${((timer['PrePaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60}');
    final post = TextEditingController(
        text: '${((timer['PostPaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${timer['Name'] ?? l.adminSeriesFallback}'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: pre,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: l.adminStartBefore, suffixText: 'min'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: post,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: l.adminStopAfter, suffixText: 'min'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave)),
        ],
      ),
    );
    if (ok != true) return;
    final preMin = int.tryParse(pre.text) ?? 0;
    final postMin = int.tryParse(post.text) ?? 0;
    final updated = <String, dynamic>{
      ...timer,
      'PrePaddingSeconds': preMin * 60,
      'PostPaddingSeconds': postMin * 60,
      'IsPrePaddingRequired': preMin > 0,
      'IsPostPaddingRequired': postMin > 0,
    };
    try {
      await ref.read(jellyfinClientProvider).updateSeriesTimer(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          id: '${timer['Id']}',
          timer: updated);
      ref.invalidate(adminSeriesTimersProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.adminDvrTitle),
          bottom: TabBar(tabs: [
            Tab(text: l.adminTabScheduled),
            Tab(text: l.adminTabSeries),
            Tab(text: l.adminTabRecorded),
          ]),
        ),
        body: TabBarView(
          children: [
            _dvrList(
              context,
              async: ref.watch(adminTimersProvider),
              empty: l.adminNoScheduledRecordings,
              onInvalidate: () => ref.invalidate(adminTimersProvider),
              tile: (t) => ListTile(
                leading: const Icon(Icons.fiber_manual_record_rounded,
                    color: Colors.red),
                title: Text('${t['Name'] ?? '—'}'),
                subtitle: Text(_timerSubtitle(t),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: l.commonCancel,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _cancelTimer(ref, '${t['Id'] ?? ''}'),
                ),
              ),
            ),
            _dvrList(
              context,
              async: ref.watch(adminSeriesTimersProvider),
              empty: l.adminNoSeriesRules,
              onInvalidate: () => ref.invalidate(adminSeriesTimersProvider),
              tile: (t) => ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: Text('${t['Name'] ?? '—'}'),
                subtitle: Text(l.adminSeriesPad(
                    ((t['PrePaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60,
                    ((t['PostPaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60)),
                onTap: () => _editSeriesPadding(context, ref, t),
                trailing: IconButton(
                  tooltip: l.commonDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _cancelSeries(ref, '${t['Id'] ?? ''}'),
                ),
              ),
            ),
            _RecordedTab(onDelete: (id) => _deleteRecording(ref, id)),
          ],
        ),
      ),
    );
  }

  static String _timerSubtitle(Map<String, dynamic> t) {
    final start = DateTime.tryParse('${t['StartDate'] ?? ''}')?.toLocal();
    final chan = '${t['ChannelName'] ?? ''}';
    final when = start == null
        ? ''
        : '${start.month}/${start.day} '
            '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return [chan, when].where((x) => x.isNotEmpty).join('  ·  ');
  }

  Widget _dvrList(
    BuildContext context, {
    required AsyncValue<List<Map<String, dynamic>>> async,
    required String empty,
    required VoidCallback onInvalidate,
    required Widget Function(Map<String, dynamic>) tile,
  }) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: '$e', onRetry: onInvalidate),
      data: (list) => list.isEmpty
          ? Center(child: Text(empty))
          : RefreshIndicator(
              onRefresh: () async => onInvalidate(),
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => tile(list[i]),
              ),
            ),
    );
  }
}

/// The Recorded tab of the DVR screen: completed recordings, playable and
/// deletable.
class _RecordedTab extends ConsumerWidget {
  final void Function(String id) onDelete;
  const _RecordedTab({required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(adminRecordingsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(adminRecordingsProvider)),
      data: (list) => list.isEmpty
          ? Center(child: Text(l.adminNoRecordings))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminRecordingsProvider),
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return ListTile(
                    leading: const Icon(Icons.video_file_rounded),
                    title: Text(r.name),
                    subtitle: r.overview == null
                        ? null
                        : Text(r.overview!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => context.push('/item', extra: r),
                    trailing: IconButton(
                      tooltip: l.commonDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => onDelete(r.id),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Client devices that have connected to the server, with deauthorize.
class AdminDevicesScreen extends ConsumerWidget {
  const AdminDevicesScreen({super.key});

  Future<void> _delete(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .deleteDevice(baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminDevicesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final devices = ref.watch(adminDevicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminDevicesTitle)),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            message: '$e', onRetry: () => ref.invalidate(adminDevicesProvider)),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.adminNoDevices))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminDevicesProvider),
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = list[i];
                    final user = '${d['LastUserName'] ?? ''}';
                    final app = '${d['AppName'] ?? ''}'
                        '${d['AppVersion'] != null ? ' ${d['AppVersion']}' : ''}';
                    return ListTile(
                      leading: const Icon(Icons.devices_other_rounded),
                      title: Text('${d['Name'] ?? d['CustomName'] ?? '—'}'),
                      subtitle: Text(
                          [app, user].where((x) => x.isNotEmpty).join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: l.commonRemove,
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(ref, '${d['Id'] ?? ''}'),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// Schedules Direct setup, mirroring the official dashboard's flow: sign in to
/// validate the account (which creates the provider and returns its id), then
/// pick a country + postal code to look up lineups, and save the chosen one.
class _SchedulesDirectDialog extends ConsumerStatefulWidget {
  const _SchedulesDirectDialog();

  @override
  ConsumerState<_SchedulesDirectDialog> createState() =>
      _SchedulesDirectDialogState();
}

class _SchedulesDirectDialogState
    extends ConsumerState<_SchedulesDirectDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _zip = TextEditingController();

  int _step = 0; // 0 = credentials, 1 = lineup
  bool _busy = false;
  String? _error;
  String? _providerId;
  Map<String, dynamic>? _countries;
  String? _country;
  List<({String id, String name})> _lineups = const [];
  String? _lineupId;
  bool _enableAllTuners = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _zip.dispose();
    super.dispose();
  }

  // The dashboard hashes the password client-side; the server stores it as-is.
  String get _hashedPassword =>
      sha1.convert(utf8.encode(_pass.text)).toString();

  Map<String, dynamic> _info({String? listingsId}) => {
        if (_providerId != null && _providerId!.isNotEmpty) 'Id': _providerId,
        'Type': 'SchedulesDirect',
        'Username': _user.text.trim(),
        'Password': _hashedPassword,
        'EnableAllTuners': _enableAllTuners,
        if (_country != null) 'Country': _country,
        if (_zip.text.trim().isNotEmpty) 'ZipCode': _zip.text.trim(),
        'ListingsId': ?listingsId,
      };

  /// Flattens Schedules Direct's region-grouped country list.
  List<({String code, String name})> get _countryOptions {
    final out = <({String code, String name})>[];
    final c = _countries;
    if (c == null) return out;
    for (final region in c.values) {
      if (region is! List) continue;
      for (final m in region.whereType<Map>()) {
        final code = '${m['shortName'] ?? ''}';
        if (code.isEmpty) continue;
        out.add((code: code, name: '${m['fullName'] ?? code}'));
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<void> _signIn() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(jellyfinClientProvider);
      final saved = await client.saveListingProvider(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        info: _info(),
        validateLogin: true,
      );
      _providerId = '${saved['Id'] ?? ''}';
      final countries = await client.getSchedulesDirectCountries(
          baseUrl: s.baseUrl, token: s.accessToken);
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _step = 1;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _findLineups() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _country == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _lineups = const [];
      _lineupId = null;
    });
    try {
      final lineups =
          await ref.read(jellyfinClientProvider).getListingProviderLineups(
                baseUrl: s.baseUrl,
                token: s.accessToken,
                providerId: _providerId ?? '',
                country: _country!,
                location: _zip.text.trim(),
              );
      if (!mounted) return;
      setState(() {
        _lineups = lineups;
        _lineupId = lineups.isNotEmpty ? lineups.first.id : null;
        _busy = false;
        if (lineups.isEmpty) {
          _error = AppLocalizations.of(context).adminNoLineups;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _lineupId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(jellyfinClientProvider).saveListingProvider(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            info: _info(listingsId: _lineupId),
            validateListings: true,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Schedules Direct'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == 0) ...[
                TextField(
                  controller: _user,
                  autofocus: true,
                  decoration: InputDecoration(labelText: loc.adminUsername),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: InputDecoration(labelText: loc.adminPassword),
                  onSubmitted: (_) => _busy ? null : _signIn(),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: loc.adminCountry),
                  items: [
                    for (final c in _countryOptions)
                      DropdownMenuItem(
                          value: c.code,
                          child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _zip,
                        decoration: InputDecoration(
                            labelText: loc.adminPostalCode, hintText: '10001'),
                        onSubmitted: (_) => _busy ? null : _findLineups(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed:
                          (_busy || _country == null) ? null : _findLineups,
                      style: kInlineButtonStyle,
                      child: Text(loc.adminFindLineups),
                    ),
                  ],
                ),
                if (_lineups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _lineupId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: loc.adminLineup),
                    items: [
                      for (final l in _lineups)
                        DropdownMenuItem(
                            value: l.id,
                            child:
                                Text(l.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _lineupId = v),
                  ),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.adminEnableAllTuners),
                  value: _enableAllTuners,
                  onChanged: (v) => setState(() => _enableAllTuners = v),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(loc.commonCancel),
        ),
        if (_step == 0)
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(loc.commonSignIn),
          )
        else
          FilledButton(
            onPressed: (_busy || _lineupId == null) ? null : _save,
            child: Text(loc.commonSave),
          ),
      ],
    );
  }
}

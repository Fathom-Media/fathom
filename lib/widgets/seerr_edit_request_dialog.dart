import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/seerr_options.dart';
import '../models/seerr_request.dart';
import '../state/seerr_providers.dart';
import '../theme/app_theme.dart';
import 'app_snack.dart';
import 'cached_image.dart';
import 'seerr_avatar.dart';

/// Edit a pending request's advanced options (quality profile, root folder,
/// language profile), matching Jellyseerr's request edit. Returns true on save.
Future<bool> showSeerrEditRequestDialog(
    BuildContext context, SeerrRequest request) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _EditRequestDialog(request: request),
  );
  return ok ?? false;
}

class _EditRequestDialog extends ConsumerStatefulWidget {
  final SeerrRequest request;
  const _EditRequestDialog({required this.request});

  @override
  ConsumerState<_EditRequestDialog> createState() => _EditRequestDialogState();
}

class _EditRequestDialogState extends ConsumerState<_EditRequestDialog> {
  SeerrServerOptions _opts = SeerrServerOptions.empty;
  List<SeerrUser> _users = const [];
  int? _serverId;
  int? _profileId;
  int? _rootFolderId;
  int? _languageProfileId;
  int? _userId;
  final Set<int> _selectedTags = {};
  bool _loading = true;
  bool _busy = false;

  bool get _isTv => widget.request.mediaType == 'tv';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(seerrClientProvider);
    if (client == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        client.servers(widget.request.mediaType),
        client.requestUsers(),
      ]);
      final servers = results[0] as List<SeerrServer>;
      final users = results[1] as List<SeerrUser>;
      final pool =
          servers.where((s) => s.is4k == widget.request.is4k).toList();
      final server = widget.request.serverId != null
          ? pool.cast<SeerrServer?>().firstWhere(
              (s) => s?.id == widget.request.serverId,
              orElse: () => pool.isNotEmpty ? pool.first : null)
          : (pool.isEmpty
              ? null
              : pool.firstWhere((s) => s.isDefault, orElse: () => pool.first));
      final opts = server == null
          ? SeerrServerOptions.empty
          : await client.serverOptions(widget.request.mediaType, server.id);
      if (!mounted) return;
      setState(() {
        _users = users;
        _serverId = server?.id;
        _opts = opts;
        _userId = users.any((u) => u.id == widget.request.requestedById)
            ? widget.request.requestedById
            : (users.isNotEmpty ? users.first.id : null);
        _selectedTags
          ..clear()
          ..addAll(widget.request.tags);
        _profileId = widget.request.profileId ?? opts.defaultProfileId;
        _languageProfileId =
            widget.request.languageProfileId ?? opts.defaultLanguageProfileId;
        _rootFolderId = opts.rootFolders
            .cast<SeerrRootFolder?>()
            .firstWhere(
                (r) =>
                    r?.path ==
                    (widget.request.rootFolder ?? opts.defaultRootFolder),
                orElse: () =>
                    opts.rootFolders.isNotEmpty ? opts.rootFolders.first : null)
            ?.id;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final client = ref.read(seerrClientProvider);
    if (client == null || _busy) return;
    setState(() => _busy = true);
    try {
      final rootFolder = _opts.rootFolders
          .cast<SeerrRootFolder?>()
          .firstWhere((r) => r?.id == _rootFolderId, orElse: () => null)
          ?.path;
      await client.editRequest(
        widget.request.id,
        mediaType: widget.request.mediaType,
        seasons: widget.request.seasons,
        profileId: _profileId,
        serverId: _serverId,
        rootFolder: rootFolder,
        languageProfileId: _isTv ? _languageProfileId : null,
        tags: _selectedTags.toList(),
        userId: _userId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showSnack(context, '$e', kind: SnackKind.error);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final detail = ref
        .watch(seerrDetailProvider((mediaType: r.mediaType, tmdbId: r.tmdbId)))
        .asData
        ?.value;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, detail?.title, detail?.backdropUrl),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: _fields(context),
              ),
            ),
            _actionsRow(context),
          ],
        ),
      ),
    );
  }

  /// The backdrop header, matching Jellyseerr's request dialogs: the title's art
  /// behind an accent heading + title + the requester's pending line.
  Widget _header(BuildContext context, String? title, String? backdropUrl) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = widget.request;
    return SizedBox(
      height: 132,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerHighest),
          if (backdropUrl != null)
            CachedImage(url: backdropUrl, errorBuilder: (_) => const SizedBox()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59000000), Color(0xD6000000)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.detailEditRequest,
                      style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w800)),
                  if (title != null && title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                  if (r.isPending && r.requestedBy != null) ...[
                    const SizedBox(height: 4),
                    Text(l.detailRequestPending(r.requestedBy!),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white70)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Root Folder is intentionally not shown (Jellyseerr's request dialog omits
    // it); its saved value is still sent so the overwrite-PUT keeps it.
    final noOptions = _opts.profiles.isEmpty &&
        _opts.tags.isEmpty &&
        _users.length <= 1 &&
        !(_isTv && _opts.languageProfiles.isNotEmpty);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (noOptions) {
      return Text(l.detailNoEditableOptions,
          style: theme.textTheme.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.detailAdvanced,
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (_opts.profiles.isNotEmpty)
          _field(
            l.detailQualityProfile,
            _dropdown(
              value: _profileId,
              items: [
                for (final p in _opts.profiles)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _profileId = v),
            ),
          ),
        if (_isTv && _opts.languageProfiles.isNotEmpty)
          _field(
            l.detailLanguageProfile,
            _dropdown(
              value: _languageProfileId,
              items: [
                for (final p in _opts.languageProfiles)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _languageProfileId = v),
            ),
          ),
        if (_opts.tags.isNotEmpty) _field(l.detailTags, _tagsDropdown()),
        if (_users.length > 1)
          _field(l.detailRequestAs, _requestAsDropdown()),
      ],
    );
  }

  Widget _actionsRow(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(l.commonCancel)),
          const SizedBox(width: 8),
          FilledButton(
            style: kInlineButtonStyle,
            onPressed: _busy || _loading ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.commonSave),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  Widget _dropdown({
    required int? value,
    required List<DropdownMenuItem<int>> items,
    required ValueChanged<int?> onChanged,
    List<Widget> Function(BuildContext)? selectedItemBuilder,
  }) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        selectedItemBuilder: selectedItemBuilder,
        decoration: InputDecoration(
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        items: items,
        onChanged: onChanged,
      );

  /// A multi-select "Select tags" field matching Jellyseerr: a dropdown-styled
  /// box that opens a checkbox menu and shows the chosen tags as chips.
  Widget _tagsDropdown() {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selected =
        _opts.tags.where((t) => _selectedTags.contains(t.id)).toList();
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10))),
      ),
      menuChildren: [
        for (final t in _opts.tags)
          CheckboxMenuButton(
            value: _selectedTags.contains(t.id),
            closeOnActivate: false,
            onChanged: (on) => setState(() {
              if (on == true) {
                _selectedTags.add(t.id);
              } else {
                _selectedTags.remove(t.id);
              }
            }),
            child: Text(t.label),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: selected.isEmpty
                    ? Text(l.detailSelectTags,
                        style: TextStyle(color: scheme.onSurfaceVariant))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in selected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(t.label,
                                  style: TextStyle(
                                      fontSize: 12.5, color: scheme.onSurface)),
                            ),
                        ],
                      ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestAsDropdown() => _dropdown(
        value: _userId,
        selectedItemBuilder: (context) => [
          for (final u in _users)
            Row(children: [
              SeerrAvatar(name: u.name, avatarUrl: u.avatarUrl, radius: 11),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  u.email == null ? u.name : '${u.name} (${u.email})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
        ],
        items: [
          for (final u in _users)
            DropdownMenuItem(
              value: u.id,
              child: Row(children: [
                SeerrAvatar(name: u.name, avatarUrl: u.avatarUrl, radius: 11),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    u.email == null ? u.name : '${u.name} (${u.email})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
        ],
        onChanged: (v) => setState(() => _userId = v),
      );
}

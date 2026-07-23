import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/youtube_video.dart';
import '../services/youtube_download.dart';
import '../state/preferences.dart';
import '../state/youtube_providers.dart';
import 'app_snack.dart';
import '../l10n/generated/app_localizations.dart';

/// Pick what to download: audio or video, then its format and quality.
///
/// Skipped entirely when a default is set — being asked the same question
/// every time is the thing a default exists to stop.
Future<void> showYoutubeDownloadSheet(
  BuildContext context,
  WidgetRef ref,
  YoutubeVideo video,
) async {
  final l = AppLocalizations.of(context);
  final prefs = ref.read(preferencesProvider).asData?.value ?? const Prefs();
  final options = YtDownloadOptions.fromPrefs(
      prefs.youtubeDownloadQuality, prefs.youtubeVideoContainer);
  if (options != null) {
    ref.read(youtubeDownloadsProvider.notifier).start(video, options: options);
    showSnack(context, l.ytDownloadInProgress);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DownloadSheet(video: video),
  );
}

class _DownloadSheet extends ConsumerStatefulWidget {
  final YoutubeVideo video;
  const _DownloadSheet({required this.video});

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  static const _heights = [2160, 1440, 1080, 720, 480, 360];
  static const _bitrates = [320, 256, 192, 128];

  bool _video = true; // else audio
  YtVideoContainer _container = YtVideoContainer.mp4;
  int _height = 1080;
  YtAudioFormat _audioFormat = YtAudioFormat.m4a;
  int _bitrate = 320;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs?.youtubeVideoContainer == 'mkv') {
      _container = YtVideoContainer.mkv;
    }
    // Start on valid choices when ffmpeg is missing (only M4A / <=360p MP4 work).
    final hasFfmpeg =
        ref.read(ffmpegAvailableProvider).asData?.value ?? true;
    if (!hasFfmpeg) {
      _container = YtVideoContainer.mp4;
      _height = 360;
    }
  }

  void _commit() {
    final options = _video
        ? YtDownloadOptions(
            kind: YtDownloadKind.video,
            preferredHeight: _height,
            container: _container,
          )
        : YtDownloadOptions(
            kind: YtDownloadKind.audio,
            audioFormat: _audioFormat,
            audioBitrate: _bitrate,
          );
    ref.read(youtubeDownloadsProvider.notifier).start(widget.video,
        options: options);
    Navigator.pop(context);
    showSnack(context, AppLocalizations.of(context).ytDownloadInProgress);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFfmpeg = ref.watch(ffmpegAvailableProvider).asData?.value ?? true;
    final mkv = _container == YtVideoContainer.mkv;

    // Whether the current selection can actually run.
    final valid = _video
        ? (hasFfmpeg || (!mkv && _height <= 360))
        : (hasFfmpeg || _audioFormat == YtAudioFormat.m4a);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.ytDownload,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(widget.video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),

                  if (!hasFfmpeg) ...[
                    const SizedBox(height: 12),
                    _FfmpegNote(),
                  ],

                  const SizedBox(height: 18),
                  _label(theme, l.ytType),
                  _chips([
                    _chip(l.ytVideo, _video, () => setState(() => _video = true)),
                    _chip(l.ytAudio, !_video,
                        () => setState(() => _video = false)),
                  ]),

                  if (_video) ...[
                    const SizedBox(height: 16),
                    _label(theme, l.ytContainer),
                    _chips([
                      _chip('MP4', !mkv,
                          () => setState(() => _container = YtVideoContainer.mp4)),
                      _chip('MKV', mkv,
                          hasFfmpeg
                              ? () => setState(
                                  () => _container = YtVideoContainer.mkv)
                              : null),
                    ]),
                    const SizedBox(height: 16),
                    _label(theme, l.ytQuality),
                    _chips([
                      for (final h in _heights)
                        _chip('${h}p', _height == h,
                            (hasFfmpeg || (!mkv && h <= 360))
                                ? () => setState(() => _height = h)
                                : null),
                    ]),
                  ] else ...[
                    const SizedBox(height: 16),
                    _label(theme, l.ytFormat),
                    _chips([
                      _chip('M4A', _audioFormat == YtAudioFormat.m4a,
                          () => setState(
                              () => _audioFormat = YtAudioFormat.m4a)),
                      _chip('MP3', _audioFormat == YtAudioFormat.mp3,
                          hasFfmpeg
                              ? () => setState(
                                  () => _audioFormat = YtAudioFormat.mp3)
                              : null),
                    ]),
                    if (_audioFormat == YtAudioFormat.mp3) ...[
                      const SizedBox(height: 16),
                      _label(theme, l.ytBitrate),
                      _chips([
                        for (final b in _bitrates)
                          _chip('$b kbps', _bitrate == b,
                              () => setState(() => _bitrate = b)),
                      ]),
                    ],
                  ],

                  const SizedBox(height: 16),
                  Text(_summary(),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: valid ? _commit : null,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(l.ytDownload),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A one-line plain-English description of what the current choice produces.
  String _summary() {
    final l = AppLocalizations.of(context);
    if (!_video) {
      return _audioFormat == YtAudioFormat.mp3
          ? l.ytSummaryMp3(_bitrate)
          : l.ytSummaryM4a;
    }
    final box = _container == YtVideoContainer.mkv ? 'MKV' : 'MP4';
    if (_height > 360) {
      return l.ytSummaryMerged(_height, box);
    }
    return _container == YtVideoContainer.mkv
        ? l.ytSummaryRemuxMkv(_height)
        : l.ytSummarySingle(_height, box);
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _chips(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);

  Widget _chip(String label, bool selected, VoidCallback? onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: onTap == null ? null : (_) => onTap(),
      );
}

class _FfmpegNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l.ytFfmpegNote,
            style:
                theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

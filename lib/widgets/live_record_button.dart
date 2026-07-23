import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/admin_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';

enum _RecState { off, single, series }

/// The record control for a live channel, cycling the way the Jellyfin apps do:
/// press once to record the current program, again to record the whole series,
/// and a third time to stop.
///
/// The first two presses act immediately rather than prompting: while you're
/// watching, hitting record should just record.
class LiveRecordButton extends ConsumerStatefulWidget {
  final String programId;
  const LiveRecordButton({super.key, required this.programId});

  @override
  ConsumerState<LiveRecordButton> createState() => _LiveRecordButtonState();
}

class _LiveRecordButtonState extends ConsumerState<LiveRecordButton> {
  _RecState _state = _RecState.off;
  String? _timerId;
  String? _seriesTimerId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Reads the program's real state back from the server, so the icon reflects
  /// timers set anywhere else (the guide, another client) too.
  Future<void> _refresh() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      final timers = await ref
          .read(jellyfinClientProvider)
          .getTimers(baseUrl: s.baseUrl, token: s.accessToken);
      Map<String, dynamic>? mine;
      for (final t in timers) {
        if ('${t['ProgramId']}' == widget.programId) {
          mine = t;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _timerId = mine?['Id'] as String?;
        _seriesTimerId = mine?['SeriesTimerId'] as String?;
        _state = _seriesTimerId != null
            ? _RecState.series
            : (_timerId != null ? _RecState.single : _RecState.off);
      });
    } catch (_) {
      // Leave the button in its last known state rather than nagging.
    }
  }

  Future<void> _create({required bool series}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    // Defaults carry the channel, times and the server's padding preferences.
    final timer = await client.getTimerDefaults(
        baseUrl: s.baseUrl, token: s.accessToken, programId: widget.programId);
    if (series) {
      await client.createSeriesTimer(
          baseUrl: s.baseUrl, token: s.accessToken, timer: timer);
      ref.invalidate(adminSeriesTimersProvider);
    } else {
      await client.createTimer(
          baseUrl: s.baseUrl, token: s.accessToken, timer: timer);
    }
    ref.invalidate(adminTimersProvider);
    await _refresh();
  }

  Future<void> _stop({required bool series}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    final seriesId = _seriesTimerId;
    final timerId = _timerId;
    if (series && seriesId != null) {
      await client.cancelSeriesTimer(
          baseUrl: s.baseUrl, token: s.accessToken, id: seriesId);
      ref.invalidate(adminSeriesTimersProvider);
    } else if (timerId != null) {
      await client.cancelTimer(
          baseUrl: s.baseUrl, token: s.accessToken, timerId: timerId);
    }
    ref.invalidate(adminTimersProvider);
    await _refresh();
  }

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (_state) {
        case _RecState.off:
          await _create(series: false);
          messenger.showSnackBar(
              SnackBar(content: Text(l.playerRecordingProgram)));
        case _RecState.single:
          await _create(series: true);
          messenger.showSnackBar(
              SnackBar(content: Text(l.playerRecordingEveryEpisode)));
        case _RecState.series:
          await _askToStop();
      }
    } on JellyfinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Only the third press asks anything, and only because stopping is the
  /// destructive one.
  Future<void> _askToStop() async {
    final l = AppLocalizations.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.playerStopRecordingTitle),
        content: Text(l.playerStopRecordingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: Text(l.playerKeepRecording),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'program'),
            child: Text(l.playerStopThisProgram),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'series'),
            child: Text(l.playerStopSeries),
          ),
        ],
      ),
    );
    if (choice == 'program') {
      await _stop(series: false);
    } else if (choice == 'series') {
      await _stop(series: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, tooltip) = switch (_state) {
      _RecState.off => (Icons.fiber_manual_record_rounded, l.playerRecord),
      _RecState.single => (
          Icons.fiber_manual_record_rounded,
          l.playerRecordingTapSeries
        ),
      _RecState.series => (
          Icons.fiber_smart_record_rounded,
          l.playerRecordingSeriesTapStop
        ),
    };
    return IconButton(
      tooltip: tooltip,
      iconSize: 22,
      onPressed: _busy ? null : _tap,
      icon: Icon(
        icon,
        // Red once it's actually recording; plain white when it isn't.
        color: _state == _RecState.off ? Colors.white : Colors.redAccent,
      ),
    );
  }
}

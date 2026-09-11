import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/sleep_timer.dart';
import 'meta_pill.dart';

/// "23m", or seconds in the final minute.
String sleepRemainingLabel(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds.clamp(0, 59)}s';
  return fmtRuntime((d.inSeconds / 60).ceil());
}

/// Picks or changes the sleep timer. [endOfItemLabel] ("End of Track", "End of
/// Episode") adds the stop-at-the-end option; leave it null where there's no
/// end to stop at (radio, live TV).
Future<void> showSleepTimerSheet(BuildContext context, {String? endOfItemLabel}) {
  return showModalBottomSheet<void>(
    context: context,
    // Sized to its content rather than the default half-height, which left
    // the "End of ..." option below the fold on a short screen.
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SleepTimerSheet(endOfItemLabel: endOfItemLabel),
  );
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet({this.endOfItemLabel});
  final String? endOfItemLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(sleepTimerProvider);
    final c = ref.read(sleepTimerProvider.notifier);
    void pick(VoidCallback set) {
      set();
      Navigator.of(context).pop();
    }

    // All in minutes, so the list reads as one scale.
    final options = [
      for (final m in const [15, 30, 45, 60, 90, 120])
        (l.sleepTimerMinutes(m), Duration(minutes: m)),
    ];
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(l.sleepTimer,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (state.active)
            ListTile(
              autofocus: true,
              leading: Icon(Icons.bedtime_rounded,
                  color: theme.colorScheme.primary),
              title: _Countdown(state: state),
              trailing: TextButton(
                onPressed: () => pick(c.cancel),
                child: Text(l.sleepTimerTurnOff),
              ),
            ),
          for (final (i, (label, d)) in options.indexed)
            ListTile(
              autofocus: !state.active && i == 0,
              leading: const Icon(Icons.timer_outlined),
              title: Text(label),
              onTap: () => pick(() => c.startTimed(d)),
            ),
          if (endOfItemLabel != null)
            ListTile(
              leading: const Icon(Icons.last_page_rounded),
              title: Text(endOfItemLabel!),
              selected: state.mode == SleepMode.endOfItem,
              onTap: () => pick(c.startEndOfItem),
            ),
        ],
      ),
    );
  }
}

/// "Stops in 23m" that ticks down, or "Stops at the end of this one".
class _Countdown extends StatefulWidget {
  const _Countdown({required this.state});
  final SleepTimerState state;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final endsAt = widget.state.endsAt;
    if (endsAt == null) return Text(l.sleepTimerAfterThis);
    return Text(l.sleepTimerStopsIn(
        sleepRemainingLabel(endsAt.difference(DateTime.now()))));
  }
}

/// A top-bar button for the sleep timer: a moon, lit in the accent color with
/// the time left while it's running.
class SleepTimerButton extends ConsumerStatefulWidget {
  const SleepTimerButton({super.key, this.endOfItemLabel});
  final String? endOfItemLabel;

  @override
  ConsumerState<SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends ConsumerState<SleepTimerButton> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _ticking(bool on) {
    if (on && _tick == null) {
      _tick = Timer.periodic(
          const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    } else if (!on) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(sleepTimerProvider);
    final endsAt = state.endsAt;
    _ticking(endsAt != null);
    final accent = Theme.of(context).colorScheme.primary;
    final icon = Icon(
      state.active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
      color: state.active ? accent : null,
    );
    return IconButton(
      tooltip: l.sleepTimer,
      onPressed: () =>
          showSleepTimerSheet(context, endOfItemLabel: widget.endOfItemLabel),
      icon: endsAt == null
          ? icon
          : Badge(
              label: Text(sleepRemainingLabel(endsAt.difference(DateTime.now()))),
              backgroundColor: accent,
              textColor: Theme.of(context).colorScheme.onPrimary,
              child: icon,
            ),
    );
  }
}

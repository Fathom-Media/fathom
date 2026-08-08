import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';
import '../state/session_controller.dart';
import '../state/syncplay.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/user_avatar.dart';

/// Watch Together (SyncPlay) management panel: create or join a group, see who
/// is in the one you're in, and leave. Reached from the profile menu. Actual
/// playback syncing happens once everyone opens the same title.
class SyncPlayScreen extends ConsumerStatefulWidget {
  const SyncPlayScreen({super.key});

  @override
  ConsumerState<SyncPlayScreen> createState() => _SyncPlayScreenState();
}

class _SyncPlayScreenState extends ConsumerState<SyncPlayScreen> {
  @override
  void initState() {
    super.initState();
    // Re-fetch the group list every time the panel opens, the way jellyfin-web
    // does: a group another user just created (idle groups included) should show
    // up without needing a manual refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(syncPlayGroupsProvider);
    });
  }

  Future<void> _create(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.appCreateGroup),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.appGroupName,
          hint: l.appGroupName,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.appCreate)),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(syncPlayControllerProvider.notifier).create(name.trim());
      messenger.showSnackBar(SnackBar(content: Text(l.appGroupCreated)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _join(BuildContext context, String groupId) async {
    try {
      await ref.read(syncPlayControllerProvider.notifier).join(groupId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final inGroup = ref.watch(syncPlayControllerProvider);
    final groups = ref.watch(syncPlayGroupsProvider);
    final controller = ref.read(syncPlayControllerProvider.notifier);
    final me = ref.watch(sessionControllerProvider).asData?.value?.userName;

    final list = groups.asData?.value ?? const <Map<String, dynamic>>[];
    Map<String, dynamic>? mine;
    if (inGroup) {
      for (final g in list) {
        final members =
            (g['Participants'] as List?)?.cast<String>() ?? const [];
        if (members.contains(me)) {
          mine = g;
          break;
        }
      }
    }
    // Every OTHER group on the server (idle ones included — the server lists
    // them). Shown regardless of our own membership so an existing group is
    // always visible; Join is only enabled when we're not already in one.
    final others =
        list.where((g) => '${g['GroupId']}' != '${mine?['GroupId']}').toList();

    // Build the list children imperatively (no collection if/for), so the group
    // rows are unambiguously added and slotted into the ListView.
    final children = <Widget>[
      if (inGroup)
        _CurrentGroup(group: mine, onLeave: controller.leave)
      else
        _Intro(onCreate: () => _create(context)),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(inGroup ? l.appOtherGroups : l.appOpenGroups,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
    ];
    if (others.isNotEmpty) {
      for (final g in others) {
        children.add(_GroupTile(
          group: g,
          canJoin: !inGroup,
          onJoin: () => _join(context, '${g['GroupId']}'),
        ));
      }
    } else if (groups.isLoading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (groups.hasError) {
      children.add(_InlineError(
        message: '${groups.error}',
        onRetry: () => ref.invalidate(syncPlayGroupsProvider),
      ));
    } else {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          inGroup ? l.appNoOtherGroups : l.appNoActiveGroups,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appWatchTogether),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(syncPlayGroupsProvider),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: children),
    );
  }
}

/// A slim inline error row with a retry, used for the group-list area.
class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.appCouldntLoadGroups(message),
                style: TextStyle(color: scheme.error)),
          ),
          TextButton(onPressed: onRetry, child: Text(l.commonRetry)),
        ],
      ),
    );
  }
}

/// Short explainer + the Create action, shown when you're not in a group.
class _Intro extends StatelessWidget {
  final VoidCallback onCreate;
  const _Intro({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.appSyncPlayIntro,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          // Land the remote on the primary action when the panel opens on TV, so
          // DOWN then steps into the (now focusable) group list below.
          autofocus: isTvDevice,
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: Text(l.appCreateGroup),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
        ),
      ],
    );
  }
}

/// The card for the group you're currently in: name, members, and Leave.
class _CurrentGroup extends ConsumerWidget {
  final Map<String, dynamic>? group;
  final Future<void> Function() onLeave;
  const _CurrentGroup({required this.group, required this.onLeave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final users = ref.watch(syncPlayUsersProvider).asData?.value ?? const {};
    final theme = Theme.of(context);
    final name = '${group?['GroupName'] ?? l.appWatchTogetherGroup}';
    final members =
        (group?['Participants'] as List?)?.cast<String>() ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No Expanded/flex — it collapses on this screen; use a
                // self-sizing row with a width-capped title instead.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_rounded,
                        color: scheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    _LiveBadge(color: scheme.onPrimaryContainer),
                  ],
                ),
                const SizedBox(height: 4),
                Text(l.appGroupConnected,
                    style: TextStyle(
                        color:
                            scheme.onPrimaryContainer.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (members.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(l.appMembers(members.length),
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in members)
                Chip(
                  avatar: JellyfinAvatar(
                    userId: '${users[m]?['Id'] ?? ''}',
                    name: m,
                    tag: users[m]?['PrimaryImageTag'] as String?,
                    radius: 11,
                  ),
                  label: Text(m),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        OutlinedButton.icon(
          onPressed: onLeave,
          icon: Icon(Icons.logout_rounded, color: scheme.error),
          label: Text(l.appLeaveGroup,
              style: TextStyle(color: scheme.error)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            side: BorderSide(color: scheme.error),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.appLeaveGroupHint,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A joinable group row: name, member summary, and a Join button. When [canJoin]
/// is false (we're already in a group) the button is disabled with a hint.
class _GroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool canJoin;
  final VoidCallback onJoin;
  const _GroupTile(
      {required this.group, required this.canJoin, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final participants =
        (group['Participants'] as List?)?.cast<String>() ?? const [];
    final subtitle = participants.isEmpty
        ? l.appNoOneWatching
        : l.appWatchingList(participants.length, participants.join(', '));
    // Flex layout (Expanded) mysteriously collapses this row on this screen even
    // with a tight width, so we use a self-sizing row (the shape that renders)
    // and make the WHOLE row tappable to join, with a text "Join" affordance
    // instead of a FilledButton (which also wouldn't paint here).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // On TV the row is a bare GestureDetector (no focus node), so a D-pad can't
      // land on it — this is why DOWN couldn't reach the joinable groups.
      // TvFocusable adds the focus node + accent ring and fires onJoin on Select;
      // off TV it's a pass-through so the GestureDetector below still handles
      // mouse/touch taps unchanged.
      child: TvFocusable(
        onTap: canJoin ? onJoin : null,
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canJoin ? onJoin : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 68,
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Full-width row so the Join affordance sits hard right (a Spacer
              // pushes it there). Expanded on the title column collapsed here in
              // the past, so keep the width-capped column + Spacer instead.
              child: Row(
                children: [
                  Icon(Icons.groups_rounded, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${group['GroupName'] ?? l.appGroup}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, height: 1.25)),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.25,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    canJoin ? l.appJoin : l.appInAGroup,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          canJoin ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (canJoin)
                    Icon(Icons.chevron_right_rounded, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny pulsing "Live" pill for the current-group card header.
class _LiveBadge extends StatelessWidget {
  final Color color;
  const _LiveBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 5),
          Text(l.appActive,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

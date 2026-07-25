import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../state/notifications_controller.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/seerr_providers.dart';
import '../state/seerr_request_watcher.dart';
import '../state/session_controller.dart';
import '../state/syncplay.dart';
import '../state/ui_providers.dart';
import '../state/updates.dart';
import '../widgets/window_frame.dart';
import '../state/youtube_providers.dart';
import '../widgets/glass.dart';
import '../widgets/app_logo.dart';
import '../widgets/mini_player.dart';
import '../widgets/mini_video.dart';
import '../widgets/user_avatar.dart';
import '../widgets/ui_common.dart';

typedef _Dest = ({String route, IconData icon, String label});

/// Wraps the signed-in content routes with a desktop navigation rail and docks
/// the mini now-playing bar at the bottom. Full-screen routes (video player,
/// now-playing, auth) sit outside this.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final extended = ref.watch(railExtendedProvider);
    // Prefer the live policy; fall back to the stored session flag while it loads.
    final liveAdmin = ref.watch(currentUserProvider).asData?.value?.isAdministrator;
    final storedAdmin =
        ref.watch(sessionControllerProvider).asData?.value?.isAdmin ?? false;
    final isAdmin = liveAdmin ?? storedAdmin;
    final seerrOn = ref.watch(seerrConfiguredProvider);
    final youtubeOn = ref.watch(youtubeEnabledProvider);
    // Keep the Seerr request poller alive for the app's lifetime (no-op until
    // Seerr is configured), so request status changes fire notifications.
    ref.watch(seerrRequestWatcherProvider);
    // Only surface Live TV when the server actually has a Live TV library.
    final views = ref.watch(userViewsProvider).asData?.value;
    final hasLiveTv =
        views?.any((v) => v.collectionType == 'livetv') ?? true;

    // Search sits second — it's a primary action, not a buried library tool.
    final destinations = <_Dest>[
      (route: '/home', icon: Icons.home_rounded, label: l.appNavHome),
      (route: '/search', icon: Icons.search_rounded, label: l.commonSearch),
      (
        route: '/libraries',
        icon: Icons.video_library_rounded,
        label: l.appNavLibraries
      ),
      (route: '/favorites', icon: Icons.favorite_rounded, label: l.appNavFavorites),
      if (hasLiveTv)
        (route: '/livetv', icon: Icons.live_tv_rounded, label: l.appNavLiveTv),
      if (seerrOn)
        (
          route: '/discover',
          icon: Icons.travel_explore_rounded,
          label: 'Seerr'
        ),
      if (youtubeOn)
        (
          route: '/youtube',
          icon: Icons.smart_display_rounded,
          label: 'YouTube'
        ),
    ];
    final scheme = Theme.of(context).colorScheme;

    const dur = Duration(milliseconds: 240);
    const curve = Curves.easeOutCubic;
    final width = extended ? 228.0 : 76.0;

    final sidebar = Column(
      children: [
        _BrandHeader(
          extended: extended,
          onToggle: () => ref.read(railExtendedProvider.notifier).toggle(),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final d in destinations)
                if (d.route == '/libraries') ...[
                  _LibrariesNav(extended: extended, location: location),
                  _BrowseNav(extended: extended, location: location),
                ] else
                  _NavTile(
                    label: d.label,
                    extended: extended,
                    selected: location.startsWith(d.route),
                    icon: d.route == '/discover' ? null : d.icon,
                    iconBuilder: d.route == '/discover'
                        ? (color) => _SeerrIcon(color: color)
                        : null,
                    onTap: () => context.go(d.route),
                  ),
            ],
          ),
        ),
        // An update indicator (only when a newer release is available) sits with
        // the notifications and account controls at the foot of the rail.
        _UpdateRailButton(extended: extended),
        _NotifBell(extended: extended),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
          child: _ProfileMenu(isAdmin: isAdmin, extended: extended),
        ),
      ],
    );

    // A Material ancestor so all shell chrome (profile menu, tooltips, ink)
    // always has one, regardless of what the child route provides.
    return Material(
      color: scheme.surface,
      child: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                // An accent wash across the whole surface. It now shows through
                // the (transparent) content too, giving the app a soft ambient
                // depth behind cards and bars rather than a flat slab.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                              scheme.primary.withValues(alpha: 0.10),
                              scheme.surface),
                          scheme.surface,
                          Color.alphaBlend(
                              scheme.tertiary.withValues(alpha: 0.06),
                              scheme.surface),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
                // Routed content, inset for the sidebar. Transparent so the
                // ambient wash reads behind it.
                AnimatedPositioned(
                  duration: dur,
                  curve: curve,
                  left: width,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(color: Colors.transparent, child: child),
                ),
                // Frosted glass sidebar floating over the wash.
                AnimatedPositioned(
                  duration: dur,
                  curve: curve,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: GlassSurface(
                    blur: 26,
                    opacity: 0.55,
                    border: Border(
                      right: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    // Keep the sidebar's controls clear of the window title bar
                    // while the glass itself runs to the top edge.
                    child: SafeArea(
                      top: true,
                      right: false,
                      bottom: false,
                      child: sidebar,
                    ),
                  ),
                ),
                // Floating minimized video (picture-in-picture).
                const MiniVideo(),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}

/// A slim bar shown when the active server can't be reached, with a shortcut to
/// what's still available offline: downloads.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(serverReachableProvider).asData?.value ?? true;
    if (reachable) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 8 + (isDesktopWindowFrame ? kWindowControlsWidth : 0), 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.appServerUnreachableOffline,
                  style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => context.push('/downloads'),
              style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer),
              child: Text(l.appDownloads),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rail-foot indicator shown only when a newer release is available. Kicks
/// the throttled startup check on first build, then watches the result; tapping
/// it opens the Updates screen. Accent-tinted so it reads as an action, and it
/// simply disappears once you're on the latest version.
class _UpdateRailButton extends ConsumerStatefulWidget {
  final bool extended;
  const _UpdateRailButton({required this.extended});

  @override
  ConsumerState<_UpdateRailButton> createState() => _UpdateRailButtonState();
}

class _UpdateRailButtonState extends ConsumerState<_UpdateRailButton> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prefs = ref.read(preferencesProvider).asData?.value;
      if (prefs?.updateCheckOnStartup ?? true) {
        ref.read(updateControllerProvider.notifier).check();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateControllerProvider).asData?.value;
    if (status == null || !status.updateAvailable) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final version = status.latest!.version;
    final icon = Icon(Icons.system_update_alt_rounded,
        color: scheme.primary, size: 23);

    void open() => context.push('/updates');

    if (!widget.extended) {
      return Tooltip(
        message: l.updateBannerAvailable(version),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _hover
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: icon),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.primary.withValues(alpha: 0.14)
                  : scheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                icon,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l.updatesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The branded header at the top of the sidebar: wordmark + collapse toggle.
class _BrandHeader extends StatelessWidget {
  final bool extended;
  final VoidCallback onToggle;
  const _BrandHeader({required this.extended, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Themed mark (tinted to the accent) rather than the full colored tile, so
    // it sits with the flat sidebar chrome like the Seerr icon does.
    final logo = FathomGlyph(size: 30, color: scheme.primary);
    if (extended) {
      return SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
          child: Row(
            children: [
              logo,
              const SizedBox(width: 10),
              Expanded(
                child: Text('Fathom',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              ),
              IconButton(
                tooltip: l.miscCollapseSidebar,
                icon: const Icon(Icons.menu_open_rounded),
                onPressed: onToggle,
              ),
            ],
          ),
        ),
      );
    }
    // Collapsed: just the expand toggle, centred.
    return SizedBox(
      height: 60,
      child: Center(
        child: IconButton(
          tooltip: l.miscExpandSidebar,
          icon: const Icon(Icons.menu_rounded),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

/// The sidebar notification bell with an unread badge; opens the notification
/// centre. The bell swings like it's being rung the moment a new notification
/// arrives, and gives a gentle re-ring on a timer while any stay unread.
class _NotifBell extends ConsumerStatefulWidget {
  final bool extended;
  const _NotifBell({this.extended = false});

  @override
  ConsumerState<_NotifBell> createState() => _NotifBellState();
}

class _NotifBellState extends ConsumerState<_NotifBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 720));
  // A decaying swing, pivoting at the top like a real handbell.
  late final Animation<double> _angle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.24), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.24, end: -0.19), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.19, end: 0.14), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.14, end: -0.09), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.09, end: 0.05), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.05, end: 0.0), weight: 2),
  ]).animate(CurvedAnimation(parent: _ring, curve: Curves.easeInOut));
  Timer? _timer;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted &&
          ref.read(unreadNotifCountProvider) > 0 &&
          !_ring.isAnimating) {
        _ring.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ring at once when the unread count climbs (a fresh notification).
    ref.listen<int>(unreadNotifCountProvider, (prev, next) {
      if (next > (prev ?? 0) && !_ring.isAnimating) _ring.forward(from: 0);
    });
    final l = AppLocalizations.of(context);
    final count = ref.watch(unreadNotifCountProvider);
    final scheme = Theme.of(context).colorScheme;
    final fg = _hover ? scheme.onSurface : scheme.onSurfaceVariant;

    final bell = AnimatedBuilder(
      animation: _angle,
      builder: (_, child) => Transform.rotate(
          angle: _angle.value, alignment: Alignment.topCenter, child: child),
      child: Icon(Icons.notifications_rounded, color: fg, size: 23),
    );
    final badged = Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: bell,
    );

    void open() => context.push('/notifications');

    if (!widget.extended) {
      return Tooltip(
        message: l.miscNotifications,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _hover
                    ? scheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: badged),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                badged,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l.miscNotifications,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single sidebar entry with an animated selection pill and hover highlight.
class _NavTile extends StatefulWidget {
  final IconData? icon;
  final Widget Function(Color color)? iconBuilder;
  final String label;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final Widget? trailing; // shown at the right edge when extended
  const _NavTile({
    required this.label,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.icon,
    this.iconBuilder,
    this.trailing,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final fg = selected
        ? scheme.primary
        : (_hover ? scheme.onSurface : scheme.onSurfaceVariant);
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.14)
        : (_hover
            ? scheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent);

    final iconWidget = widget.iconBuilder != null
        ? widget.iconBuilder!(fg)
        : Icon(widget.icon, color: fg, size: 23);

    Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: widget.extended
              ? Row(
                  children: [
                    const SizedBox(width: 16),
                    iconWidget,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: fg,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                    const SizedBox(width: 8),
                  ],
                )
              : Center(child: iconWidget),
        ),
      ),
    );

    if (!widget.extended) {
      tile = Tooltip(message: widget.label, child: tile);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: tile,
    );
  }
}

/// The Libraries nav item: tapping the row opens the full Libraries screen; the
/// chevron expands an inline list of the user's libraries (Live TV excluded —
/// it has its own section).
/// Genres, Studios, Artists, Playlists and Downloads — each has a full screen,
/// but they were reachable only as chips inside the Libraries hub. Grouped here
/// under one expandable "Browse" item so they're a tap away without crowding
/// the top level.
class _BrowseNav extends ConsumerWidget {
  final bool extended;
  final String location;
  const _BrowseNav({required this.extended, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final expanded = ref.watch(browseNavExpandedProvider);
    final items = <(String, String, IconData)>[
      (l.miscNavPlaylists, '/playlists', Icons.playlist_play_rounded),
      (l.miscNavGenres, '/genres', Icons.category_rounded),
      (l.miscNavStudios, '/studios', Icons.business_rounded),
      (l.miscNavArtists, '/artists', Icons.groups_rounded),
      (l.appDownloads, '/downloads', Icons.download_done_rounded),
    ];
    final selected = items.any((i) => location.startsWith(i.$2));

    // Collapsed: no room to expand inline, and these are distinct pages (not a
    // single hub), so tapping opens a flyout menu of the destinations.
    if (!extended) {
      return MenuAnchor(
        menuChildren: [
          for (final i in items)
            MenuItemButton(
              leadingIcon: Icon(i.$3),
              onPressed: () => context.go(i.$2),
              child: Text(i.$1),
            ),
        ],
        builder: (context, controller, _) => _NavTile(
          label: l.miscBrowse,
          icon: Icons.grid_view_rounded,
          extended: false,
          selected: selected,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    }

    return Column(
      children: [
        _NavTile(
          label: l.miscBrowse,
          icon: Icons.grid_view_rounded,
          extended: extended,
          selected: selected,
          onTap: () => ref.read(browseNavExpandedProvider.notifier).toggle(),
          trailing: AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.chevron_right_rounded,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant),
          ),
        ),
        if (extended)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: expanded ? 1 : 0,
                child: Column(
                  children: [
                    for (final i in items)
                      _NavSubTile(
                        label: i.$1,
                        icon: i.$3,
                        onTap: () => context.go(i.$2),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LibrariesNav extends ConsumerWidget {
  final bool extended;
  final String location;
  const _LibrariesNav({required this.extended, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final expanded = ref.watch(librariesNavExpandedProvider);
    final views = (ref.watch(userViewsProvider).asData?.value ??
            const <BaseItemDto>[])
        .where((v) => v.collectionType != 'livetv')
        .toList();
    final selected = location.startsWith('/libraries') ||
        location.startsWith('/library');
    final canExpand = extended && views.isNotEmpty;

    return Column(
      children: [
        _NavTile(
          label: l.appNavLibraries,
          icon: Icons.video_library_rounded,
          extended: extended,
          selected: selected,
          // Clicking the row expands the list (Fladder-style); collapsed rail
          // has no room, so it opens the full Libraries screen instead.
          onTap: () {
            if (canExpand) {
              ref.read(librariesNavExpandedProvider.notifier).toggle();
            } else {
              context.go('/libraries');
            }
          },
          trailing: canExpand
              ? AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20,
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant),
                )
              : null,
        ),
        if (extended)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: expanded ? 1 : 0,
                child: Column(
                  children: [
                    for (final v in views)
                      _NavSubTile(
                        label: v.name,
                        icon: collectionTypeIcon(v.collectionType),
                        onTap: () => context.push('/library', extra: v),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// An indented library entry shown under the expanded Libraries item.
class _NavSubTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NavSubTile(
      {required this.label, required this.icon, required this.onTap});

  @override
  State<_NavSubTile> createState() => _NavSubTileState();
}

class _NavSubTileState extends State<_NavSubTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = _hover ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 10, 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 40,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(widget.icon, size: 19, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 13.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The user menu docked at the bottom of the rail: tapping the avatar opens
/// user-specific settings, Administration (admins only), and sign out, the way
/// Jellyfin and Fladder surface account actions behind the profile picture.
class _ProfileMenu extends ConsumerWidget {
  final bool isAdmin;
  final bool extended;
  const _ProfileMenu({required this.isAdmin, required this.extended});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;
    final syncPlayOn = ref.watch(
        preferencesProvider.select((p) => p.asData?.value.syncPlayEnabled ?? true));
    final inGroup = ref.watch(syncPlayControllerProvider);
    return PopupMenuButton<String>(
      tooltip: session?.userName ?? l.miscAccount,
      offset: const Offset(56, 0),
      position: PopupMenuPosition.over,
      onSelected: (value) {
        switch (value) {
          case 'profile':
            context.push('/profile');
          case 'syncplay':
            context.push('/syncplay');
          case 'settings':
            context.push('/settings');
          case 'quickconnect':
            showDialog<void>(
                context: context,
                builder: (_) => const _QuickConnectAuthorizeDialog());
          case 'admin':
            context.push('/admin');
          case 'signout':
            ref.read(sessionControllerProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              const UserAvatar(radius: 18),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(session?.userName ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (session?.serverName != null)
                      Text(session!.serverName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (syncPlayOn)
          PopupMenuItem<String>(
            value: 'syncplay',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_rounded,
                  color: inGroup ? scheme.primary : null),
              title: Text(l.miscWatchTogether),
              subtitle: inGroup ? Text(l.miscInAGroup) : null,
              trailing: inGroup
                  ? Icon(Icons.circle, size: 10, color: scheme.primary)
                  : null,
            ),
          ),
        PopupMenuItem<String>(
          value: 'quickconnect',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: Text(l.miscQuickConnect),
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_rounded),
            title: Text(l.miscSettings),
          ),
        ),
        if (isAdmin)
          PopupMenuItem<String>(
            value: 'admin',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.admin_panel_settings_rounded),
              title: Text(l.miscAdministration),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text(l.commonSignOut, style: TextStyle(color: scheme.error)),
          ),
        ),
      ],
      child: extended
          ? SizedBox(
              height: 48,
              child: Row(
                children: [
                  // Places the avatar's centre on the same x as the nav icons
                  // and the bell above it.
                  const SizedBox(width: 12),
                  const UserAvatar(radius: 15),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      session?.userName ?? l.miscAccount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: UserAvatar(radius: 16)),
    );
  }
}

/// The Seerr nav icon: the flattened Seerr swirl, tinted to [color] so it
/// tracks the theme/accent exactly like the other line icons.
class _SeerrIcon extends StatelessWidget {
  final Color color;
  const _SeerrIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/seerr.svg',
      width: 23,
      height: 23,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Lets a signed-in user approve a Quick Connect code shown on another device.
class _QuickConnectAuthorizeDialog extends ConsumerStatefulWidget {
  const _QuickConnectAuthorizeDialog();

  @override
  ConsumerState<_QuickConnectAuthorizeDialog> createState() =>
      _QuickConnectAuthorizeDialogState();
}

class _QuickConnectAuthorizeDialogState
    extends ConsumerState<_QuickConnectAuthorizeDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _authorize() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(jellyfinClientProvider).authorizeQuickConnect(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            code: code,
          );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
            SnackBar(content: Text(l.miscDeviceApproved)));
      } else {
        setState(() => _error = l.miscCodeNotApproved);
      }
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.miscQuickConnect),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.miscEnterCodePrompt,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 6),
            onSubmitted: (_) => _busy ? null : _authorize(),
            decoration: InputDecoration(
              hintText: l.miscCode,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _authorize,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(l.miscApprove),
        ),
      ],
    );
  }
}

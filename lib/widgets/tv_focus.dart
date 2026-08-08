import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tv_mode.dart';

/// The nav rail's D-pad landing node. A content row escapes to it when the
/// remote presses LEFT past the first card; the rail assigns it to the active
/// destination so LEFT always lands on the current section. Global because the
/// rail and the content rows live in different subtrees.
final FocusNode tvNavBarNode = FocusNode(debugLabel: 'tvNavRail');

/// The content card the remote last left when it jumped to the rail, so RIGHT
/// out of the rail returns to where you were rather than the top of the page.
FocusNode? tvLastContentFocus;

/// The scope wrapping the routed content on TV. Lets the rail hand focus back
/// into content (RIGHT) and lets [TvAutofocus] focus a fresh screen's first
/// item without accidentally grabbing a rail node.
final FocusScopeNode tvContentScope = FocusScopeNode(debugLabel: 'tvContent');

/// The focusable content nodes in reading order (top-to-bottom, left-to-right).
List<FocusNode> tvContentNodesInOrder() {
  return tvContentScope.traversalDescendants
      .where((n) => n.canRequestFocus && n.context != null)
      .toList()
    ..sort((a, b) {
      final dy = a.rect.top.compareTo(b.rect.top);
      return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
    });
}

/// The logical screen size, for on-screen visibility checks.
Size _tvScreenSize() {
  final v = WidgetsBinding.instance.platformDispatcher.views.first;
  return v.physicalSize / v.devicePixelRatio;
}

/// Whether a focus node is currently on-screen (its rect overlaps the display).
/// Used so entering content from the rail always lands on something the user can
/// SEE, never a scrolled-off node (which read as a "phantom" focus).
bool _tvOnScreen(FocusNode n) {
  if (n.context == null) return false;
  final r = n.rect;
  if (r.isEmpty) return false;
  return r.overlaps(Offset.zero & _tvScreenSize());
}

/// The height of the top-chrome band (app bar back button, filter icons, section
/// header). Focus should start on the content BELOW it, not on the back button.
double get _tvHeaderCutoff => _tvScreenSize().height * 0.16;

/// The node a fresh screen should focus first: the first on-screen content item
/// BELOW the top chrome, so the remote lands on the actual movie/show/album/track
/// — not the back button.
///
/// Grids and detail screens load their data ASYNC, so for the first frames the
/// only focusables are the app bar chrome. When [preferBelowHeader] is true we
/// return null in that case, so the caller keeps retrying until real content
/// appears rather than settling on the back button. Set it false as a last
/// resort (short screens with no content below the header, e.g. an empty state)
/// so there's always some landing spot.
FocusNode? tvFirstVisibleContentNode({bool preferBelowHeader = false}) {
  final nodes = tvContentNodesInOrder();
  final visible = [for (final n in nodes) if (_tvOnScreen(n)) n];
  if (visible.isEmpty) return null;
  final headerCutoff = _tvHeaderCutoff;
  for (final n in visible) {
    if (n.rect.top >= headerCutoff) return n;
  }
  // Nothing below the header yet: either still loading (retry) or a genuinely
  // short screen (accept the top node).
  return preferBelowHeader ? null : visible.first;
}

/// Focuses the content's first item when a screen opens on TV, so the remote
/// always has a landing spot (and RIGHT from the rail into a fresh screen has
/// somewhere to go). No-op if content already holds focus (e.g. a screen set its
/// own autofocus). Rebuilt per route — key it by the location.
class TvAutofocus extends StatefulWidget {
  const TvAutofocus({super.key, required this.child});
  final Widget child;

  @override
  State<TvAutofocus> createState() => _TvAutofocusState();
}

class _TvAutofocusState extends State<TvAutofocus> {
  @override
  void initState() {
    super.initState();
    if (!isTvDevice) return;
    // Opening a screen should land focus IN that screen's content, so the remote
    // always has a visible spot (and doesn't get stranded on the rail after
    // Flutter's focus-recovery grabs it when the previous screen's card
    // unmounts). Many screens (detail/album/grids) load their data ASYNC, so the
    // first focusable may not exist for several frames — retry until it does.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocus(0));
  }

  void _tryFocus(int attempt) {
    if (!mounted) return;
    // The last attempt accepts a header-band fallback, so a screen with nothing
    // below the header (empty state, a short settings page) still gets a landing
    // spot instead of never focusing.
    final lastTry = attempt >= 15;
    final pf = FocusManager.instance.primaryFocus;
    // "Settled" means focus is on a real content item BELOW the top chrome. Focus
    // sitting on the app bar back button (which is inside the content scope, and
    // is all that exists while a grid/detail loads async) does NOT count — keep
    // trying so it moves onto the movie/album once it appears.
    final onContent = pf != null &&
        pf.context != null &&
        tvContentScope.traversalDescendants.contains(pf);
    if (onContent && pf.rect.top >= _tvHeaderCutoff) return;
    final node = tvFirstVisibleContentNode(preferBelowHeader: !lastTry);
    if (node != null) {
      node.requestFocus();
      if (!lastTry) return; // landed below the header — done
    }
    // Nothing below the header yet (still loading) — retry for a few seconds.
    if (attempt < 16) {
      Future.delayed(
          const Duration(milliseconds: 200), () => _tryFocus(attempt + 1));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A horizontal content row (poster/landscape strip) turned into a self-contained
/// D-pad group: LEFT/RIGHT walk the cards, LEFT past the first card jumps to the
/// nav rail, and UP/DOWN hand off to the neighbouring row. Wrap a row's
/// horizontal `ListView` in this ONLY on TV; elsewhere use the list directly so
/// desktop/mouse traversal is unchanged.
class TvFocusRow extends StatefulWidget {
  const TvFocusRow({super.key, required this.child});
  final Widget child;

  @override
  State<TvFocusRow> createState() => _TvFocusRowState();
}

class _TvFocusRowState extends State<TvFocusRow> {
  // A non-focusable anchor for the row: never a focus target itself, but its
  // geometry is the reference the policy uses to hand UP/DOWN to the row above
  // or below.
  final FocusNode _groupNode =
      FocusNode(debugLabel: 'tvRow', canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _groupNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: _TvRowPolicy(_groupNode),
      child: Focus(
        focusNode: _groupNode,
        canRequestFocus: false,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}

class _TvRowPolicy extends WidgetOrderTraversalPolicy {
  _TvRowPolicy(this.groupNode);
  final FocusNode groupNode;

  List<FocusNode> _cards() => groupNode.descendants
      .where((n) => n != groupNode && n.canRequestFocus && n.context != null)
      .toList()
    ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

  // Scroll the row just enough to keep the newly-focused card on-screen at the
  // leading/trailing edge. This is what lets the remote walk PAST the cards that
  // were on-screen at open: revealing a card scrolls the lazy list, which builds
  // the next cards into the cache so the following press can reach them. Without
  // this the row dead-ends at the last card that happened to be built.
  void _reveal(FocusNode n, {required bool forward}) {
    final ctx = n.context;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignmentPolicy: forward
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.up:
      case TraversalDirection.down:
        // Hand vertical moves up to the surrounding scope, anchored on the row
        // itself, so focus lands on the neighbouring row rather than the next
        // card in this one.
        return super.inDirection(groupNode, direction);
      case TraversalDirection.left:
      case TraversalDirection.right:
        final nodes = _cards();
        if (nodes.isEmpty) return super.inDirection(currentNode, direction);
        final index = nodes.indexOf(currentNode);
        if (index == -1) {
          nodes.first.requestFocus();
          return true;
        }
        if (direction == TraversalDirection.left) {
          if (index > 0) {
            nodes[index - 1].requestFocus();
            _reveal(nodes[index - 1], forward: false);
          } else {
            // Past the first card: jump to the nav rail.
            tvLastContentFocus = currentNode;
            if (tvNavBarNode.canRequestFocus &&
                tvNavBarNode.context?.mounted == true) {
              tvNavBarNode.requestFocus();
            }
          }
        } else {
          if (index < nodes.length - 1) {
            nodes[index + 1].requestFocus();
            _reveal(nodes[index + 1], forward: true);
          }
        }
        return true;
    }
  }
}

/// The content area's traversal policy on TV. Its whole job is to make the nav
/// rail reachable from EVERY screen: when LEFT is pressed and there's no
/// focusable on the same row to the left, focus jumps to the rail (instead of
/// wrapping to the previous grid row or dead-ending). RIGHT/UP/DOWN fall back to
/// normal reading-order traversal, which handles grids and lists fine.
///
/// Home's rows opt out of this by being their own [TvFocusRow] groups (their
/// policy handles LEFT-escape themselves); this policy governs every other
/// screen whose cards sit directly in the content group (grids, lists, details).
class TvContentTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.left) {
      final cur = currentNode.rect;
      FocusNode? best;
      double bestDist = double.infinity;
      for (final n in currentNode.nearestScope?.traversalDescendants ??
          const <FocusNode>[]) {
        if (n == currentNode || !n.canRequestFocus || n.context == null) {
          continue;
        }
        final r = n.rect;
        // Same-row band (vertical overlap) and genuinely to the left.
        final sameRow = cur.top < r.bottom && r.top < cur.bottom;
        if (!sameRow || r.center.dx >= cur.center.dx) continue;
        final dist = (cur.left - r.right).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = n;
        }
      }
      if (best != null) {
        best.requestFocus();
        return true;
      }
      // Nothing to the left on this row: escape to the nav rail.
      if (tvNavBarNode.canRequestFocus &&
          tvNavBarNode.context?.mounted == true) {
        tvLastContentFocus = currentNode;
        tvNavBarNode.requestFocus();
        return true;
      }
    }
    return super.inDirection(currentNode, direction);
  }
}

/// The nav-rail traversal policy: normal within the rail, but RIGHT past its
/// edge returns to the content the remote came from (or the first card).
class TvRailPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // Keep vertical moves INSIDE the rail. Directional traversal otherwise
    // crosses the group boundary, so DOWN off the last tile (the account /
    // profile tile) geometrically lands on the content hero — the reported bug.
    // Move to the nearest rail tile above/below in the same column; if there's
    // none (the top or bottom of the rail) consume the key so focus stays on the
    // tile until the user presses RIGHT (into content) or UP.
    if (direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      final cur = currentNode.rect;
      FocusNode? best;
      double bestDist = double.infinity;
      for (final n in currentNode.nearestScope?.traversalDescendants ??
          const <FocusNode>[]) {
        if (n == currentNode || !n.canRequestFocus || n.context == null) {
          continue;
        }
        final r = n.rect;
        // Same rail column: the candidate's horizontal centre falls within the
        // current tile's span (the content area sits to the right, excluded).
        if (r.center.dx < cur.left || r.center.dx > cur.right) continue;
        final isBelow = direction == TraversalDirection.down
            ? r.top > cur.top + 1
            : r.top < cur.top - 1;
        if (!isBelow) continue;
        final dist = (r.top - cur.top).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = n;
        }
      }
      if (best != null) {
        best.requestFocus();
        return true;
      }
      return true; // top/bottom of the rail: stay, don't fall into content
    }
    final handled = super.inDirection(currentNode, direction);
    if (!handled && direction == TraversalDirection.right) {
      // Prefer returning to exactly where the remote left content — but only if
      // it's still on-screen (so RIGHT never lands on a scrolled-off "phantom")
      // AND below the top chrome (so it never returns to the app bar back/filter
      // buttons, which read as "focus stuck at the top" — the exact complaint).
      final target = tvLastContentFocus;
      if (target != null &&
          target.canRequestFocus &&
          target.context?.mounted == true &&
          _tvOnScreen(target) &&
          target.rect.top >= _tvHeaderCutoff) {
        target.requestFocus();
        return true;
      }
      // Otherwise land on the first VISIBLE content item below the header, so a
      // single RIGHT always shows an obvious highlight on real content (no
      // double-press, never the back button).
      final first = tvFirstVisibleContentNode();
      if (first != null) {
        first.requestFocus();
        return true;
      }
    }
    return handled;
  }
}

/// On TV, scrolls the enclosing scroll view all the way to the top whenever
/// anything inside [child] gains focus. Used to wrap the home hero: when the
/// remote comes back UP to the hero's buttons, the framework only scrolls them
/// just into view (cutting off the art above), so this pulls the whole hero back
/// into frame like a fresh open. Off TV it's a pass-through.
class TvScrollToTopOnFocus extends StatefulWidget {
  const TvScrollToTopOnFocus({super.key, required this.child});
  final Widget child;

  @override
  State<TvScrollToTopOnFocus> createState() => _TvScrollToTopOnFocusState();
}

class _TvScrollToTopOnFocusState extends State<TvScrollToTopOnFocus> {
  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // After the framework's own ensure-visible settles, override it by
        // scrolling fully to the top so the hero art isn't clipped.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final pos = Scrollable.maybeOf(context)?.position;
          if (pos != null && pos.pixels > 0) {
            pos.animateTo(0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic);
          }
        });
      },
      child: widget.child,
    );
  }
}

/// Wraps arbitrary card content (a landscape tile, a library card, a browse
/// tile) and makes it a first-class D-pad target: it owns the [FocusNode],
/// draws a bold accent ring + glow + slight scale-up when focused, and fires
/// [onTap] on the remote's centre/select (ActivateIntent). Mouse/touch taps are
/// left to whatever tappable the child already contains (keep its InkWell but
/// pass `canRequestFocus: false` so focus isn't split between two nodes).
///
/// Use for cards that render their own artwork/ripple. For plain buttons that
/// should keep their own colours, use [TvFocusAura] instead.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.scale = 1.05,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double scale;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  // Handle the remote's OK/Select (and Enter/Space/gameButtonA) DIRECTLY on the
  // focused node. Going through ActivateIntent/Shortcuts proved unreliable here
  // (the intent didn't reach the tile's action from a lazy sliver list), but a
  // plain onKeyEvent on the focused node always fires — this is the definitive
  // activation path for D-pad Select.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.gameButtonA) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // TV only: off TV this is a pass-through, so desktop/mobile keep the child's
    // original tap/focus behaviour (no accent ring, no extra keyboard stop).
    if (!isTvDevice) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: (v) => setState(() => _focused = v),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.75),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              widget.child,
              if (_focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: widget.borderRadius,
                        border: Border.all(color: scheme.primary, width: 3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a focusable control (button, poster, tile) and draws a bold, glowing
/// "aura" plus a slight scale-up when it holds focus — the obvious D-pad
/// selection indicator for Android TV. The child keeps its own colours; the
/// aura is drawn *around* it.
///
/// The child owns the [FocusNode] (so its own tap/activate keeps working); this
/// widget only observes it. Use like:
/// ```dart
/// TvFocusAura(builder: (node) => FilledButton(focusNode: node, ...))
/// ```
class TvFocusAura extends StatefulWidget {
  const TvFocusAura({
    super.key,
    required this.builder,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.scale = 1.04,
  });

  final Widget Function(FocusNode node) builder;
  final BorderRadius borderRadius;
  final double scale;

  @override
  State<TvFocusAura> createState() => _TvFocusAuraState();
}

class _TvFocusAuraState extends State<TvFocusAura> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() {
    if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TV only: off TV, render the control with its node but no aura/scale, so
    // desktop/mobile keep the button exactly as it was.
    if (!isTvDevice) return widget.builder(_node);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.75),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: widget.builder(_node),
      ),
    );
  }
}

/// Draws an accent focus ring (and an optional slight scale) around a child that
/// ALREADY contains its own focusable — a `ListTile` or `InkWell` with an
/// `onTap`. Unlike [TvFocusable] it does NOT add a second focus node: it only
/// observes whether a descendant holds focus (`Focus.onFocusChange` reports the
/// node's `hasFocus`, which is true when a descendant is focused), so the row
/// stays a single D-pad stop and keeps its own Select/tap handling. Use for the
/// many content rows whose built-in focus tint is too faint to read across a
/// room. A no-op off TV, so desktop/mouse behaviour is unchanged.
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.scale = 1.0,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double scale;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

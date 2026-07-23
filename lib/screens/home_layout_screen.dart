import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/preferences.dart';

/// Reorder and toggle the Home screen rows (Continue Watching / Recently Added
/// / My Media), Moonfin-style. Saved to preferences.
class HomeLayoutScreen extends ConsumerWidget {
  const HomeLayoutScreen({super.key});

  static Map<String, String> _titles(AppLocalizations l) => {
        'continueWatching': l.homeLayoutContinueWatching,
        'nextUp': l.homeLayoutNextUp,
        'recentlyAdded': l.homeLayoutRecentlyAdded,
        'myMedia': l.homeLayoutMyMedia,
      };

  bool _visible(Prefs p, String id) => switch (id) {
        'continueWatching' => p.showContinueWatching,
        'nextUp' => p.showNextUp,
        'recentlyAdded' => p.showRecentlyAdded,
        'myMedia' => p.showMyMedia,
        _ => true,
      };

  Prefs _toggle(Prefs p, String id, bool v) => switch (id) {
        'continueWatching' => p.copyWith(showContinueWatching: v),
        'nextUp' => p.copyWith(showNextUp: v),
        'recentlyAdded' => p.copyWith(showRecentlyAdded: v),
        'myMedia' => p.copyWith(showMyMedia: v),
        _ => p,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final l = AppLocalizations.of(context);
    final titles = _titles(l);
    // Guard against unknown/missing ids from older prefs.
    final rows = [
      ...p.homeRowOrder.where(titles.containsKey),
      ...titles.keys.where((k) => !p.homeRowOrder.contains(k)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.homeLayoutTitle)),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                final list = [...rows];
                if (newIndex > oldIndex) newIndex -= 1;
                list.insert(newIndex, list.removeAt(oldIndex));
                c.edit((x) => x.copyWith(homeRowOrder: list));
              },
              children: [
                for (final id in rows)
                  ListTile(
                    key: ValueKey(id),
                    leading: const Icon(Icons.drag_handle_rounded),
                    title: Text(titles[id] ?? id),
                    trailing: Switch(
                      value: _visible(p, id),
                      onChanged: (v) => c.edit((x) => _toggle(x, id, v)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.video_library_outlined),
            title: Text(l.homeLayoutLatestByLibrary),
            subtitle: Text(l.homeLayoutLatestByLibrarySubtitle),
            value: p.showLibraryLatest,
            onChanged: (v) =>
                c.edit((x) => x.copyWith(showLibraryLatest: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.theater_comedy_outlined),
            title: Text(l.homeLayoutGenreRows),
            subtitle: Text(l.homeLayoutGenreRowsSubtitle),
            value: p.showGenreRows,
            onChanged: (v) => c.edit((x) => x.copyWith(showGenreRows: v)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

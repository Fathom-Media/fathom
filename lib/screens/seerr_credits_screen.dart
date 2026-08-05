import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/seerr_detail.dart';
import '../widgets/tv_focus.dart';

/// Full cast and crew for a title, as Jellyseerr's "View Full Cast" page.
class SeerrCreditsScreen extends StatelessWidget {
  final String title;
  final List<SeerrCast> cast;
  final List<SeerrCrew> crew;
  const SeerrCreditsScreen({
    super.key,
    required this.title,
    required this.cast,
    required this.crew,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (cast.isNotEmpty) ...[
            Text(l.detailCast, style: _h(theme)),
            const SizedBox(height: 12),
            _PeopleGrid(
              people: [
                for (final c in cast)
                  _Person(
                      id: c.id,
                      name: c.name,
                      role: c.character,
                      imageUrl: c.profileUrl),
              ],
            ),
          ],
          if (crew.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l.detailCrew, style: _h(theme)),
            const SizedBox(height: 12),
            _PeopleGrid(
              people: [
                for (final c in crew)
                  _Person(
                      id: c.id,
                      name: c.name,
                      role: c.job,
                      imageUrl: c.profileUrl),
              ],
            ),
          ],
        ],
      ),
    );
  }

  TextStyle? _h(ThemeData theme) =>
      theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
}

class _Person {
  final int id;
  final String name;
  final String? role;
  final String? imageUrl;
  const _Person({required this.id, required this.name, this.role, this.imageUrl});
}

class _PeopleGrid extends StatelessWidget {
  final List<_Person> people;
  const _PeopleGrid({required this.people});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 76,
        mainAxisSpacing: 10,
        crossAxisSpacing: 12,
      ),
      itemCount: people.length,
      itemBuilder: (context, i) => _PersonRow(person: people[i]),
    );
  }
}

class _PersonRow extends StatefulWidget {
  final _Person person;
  const _PersonRow({required this.person});
  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.person;
    final clickable = p.id != 0;
    final onTap =
        clickable ? () => context.push('/seerr-person', extra: p.id) : null;
    final card = MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hover
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                foregroundImage:
                    p.imageUrl != null ? NetworkImage(p.imageUrl!) : null,
                child: p.imageUrl == null
                    ? const Icon(Icons.person_rounded, size: 24)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (p.role != null && p.role!.isNotEmpty)
                      Text(p.role!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return card;
    return TvFocusable(onTap: onTap, child: card);
  }
}

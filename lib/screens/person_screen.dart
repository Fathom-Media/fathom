import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/item_grid.dart';

/// A cast/crew member's page: a profile header (photo, name, bio) with their
/// filmography as a poster grid below.
class PersonScreen extends ConsumerWidget {
  final Person person;
  const PersonScreen({super.key, required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(personItemsProvider(person.id));
    return Scaffold(
      appBar: AppBar(title: Text(person.name)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PersonHeader(person: person),
          Expanded(
            child: ItemGridBody(
              items: items,
              emptyIcon: Icons.person_rounded,
              emptyTitle: l.detailNoTitlesFound,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonHeader extends ConsumerWidget {
  final Person person;
  const _PersonHeader({required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    final detail = ref.watch(personDetailProvider(person.id)).asData?.value;
    final overview = detail?.overview;

    Widget photo() {
      final placeholder = Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.person_rounded,
            size: 56, color: scheme.onSurfaceVariant),
      );
      Widget inner = placeholder;
      if (session != null && person.primaryImageTag != null) {
        inner = Image.network(
          client.imageUrl(
            baseUrl: session.baseUrl,
            itemId: person.id,
            type: 'Primary',
            tag: person.primaryImageTag,
            maxHeight: 320,
          ),
          fit: BoxFit.cover,
          headers: headers,
          errorBuilder: (_, _, _) => placeholder,
        );
      }
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: 132, height: 176, child: inner),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          photo(),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if ((person.type ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(person.type!,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
                if (overview != null && overview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(overview,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

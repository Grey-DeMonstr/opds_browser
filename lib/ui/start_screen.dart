import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/catalog_url_formatter.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/add_edit_catalog_dialog.dart';

/// Horizontal inset shared by the section rules and every row.
const _gutter = 18.0;

class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogsAsync = ref.watch(catalogsProvider);
    final favoritesAsync = ref.watch(favoritesProvider);

    return catalogsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (catalogs) => favoritesAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
        data: (favorites) =>
            _StartScreenContent(catalogs: catalogs, favorites: favorites),
      ),
    );
  }
}

class _StartScreenContent extends ConsumerWidget {
  final List<Catalog> catalogs;
  final List<Favorite> favorites;

  const _StartScreenContent({required this.catalogs, required this.favorites});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: _gutter,
        title: const Text('OPDS Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_library_outlined),
            tooltip: 'Manage local library',
            onPressed: () => context.push('/library'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 2, bottom: 10),
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AddEditCatalogDialog(),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add catalogue'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            if (favorites.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  label: 'FAVOURITES',
                  labelColor: scheme.primary,
                  ruleColor: scheme.primary.withValues(alpha: 0.35),
                  first: true,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _FavoriteRow(
                    favorite: favorites[index],
                    catalogs: catalogs,
                  ),
                  childCount: favorites.length,
                ),
              ),
            ],
            if (catalogs.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionHeader(
                  label: 'CATALOGUES',
                  labelColor: scheme.onSurfaceVariant,
                  ruleColor: scheme.onSurface.withValues(alpha: 0.18),
                  first: favorites.isEmpty,
                ),
              ),
            if (catalogs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No catalogues yet. Tap + to add one.'),
                ),
              )
            else ...[
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _CatalogRow(catalog: catalogs[index]),
                  childCount: catalogs.length,
                ),
              ),
              // Clears the action button floating over the end of the list.
              const SliverToBoxAdapter(child: SizedBox(height: 84)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section label followed by a rule that fades out to the right — the
/// Nocturne rule treatment, anchored at the label instead of centred.
class _SectionHeader extends StatelessWidget {
  final String label;
  final Color labelColor;
  final Color ruleColor;
  final bool first;

  const _SectionHeader({
    required this.label,
    required this.labelColor,
    required this.ruleColor,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter, first ? 2 : 18, _gutter, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.4,
              color: labelColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [ruleColor, ruleColor.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared row shape: a 38px mark, a two-line stack, an overflow menu.
class _Row extends StatelessWidget {
  final Widget mark;
  final String title;
  final Widget subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  const _Row({
    super.key,
    required this.mark,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gutter, 11, 6, 11),
        child: Row(
          children: [
            mark,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.3,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle,
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// The 38px rounded square that opens every row.
class _Mark extends StatelessWidget {
  final Color background;
  final Color border;
  final Widget child;

  const _Mark({
    required this.background,
    required this.border,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: child,
    );
  }
}

/// The overflow affordance, sized so its glyph lands on the gutter while the
/// tap target stays comfortable.
class _RowMenu<T> extends StatelessWidget {
  final void Function(T) onSelected;
  final List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder;

  const _RowMenu({required this.onSelected, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      iconSize: 18,
      padding: const EdgeInsets.all(12),
      icon: Icon(Icons.more_vert, color: appPaletteOf(context).dim),
    );
  }
}

class _CatalogRow extends ConsumerWidget {
  final Catalog catalog;
  const _CatalogRow({required this.catalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return _Row(
      key: Key('catalog-${catalog.id}'),
      mark: _Mark(
        background: appPaletteOf(context).catalogMarkSurface,
        border: scheme.outlineVariant,
        child: Icon(Icons.rss_feed, size: 18, color: scheme.primary),
      ),
      title: catalog.title,
      subtitle: Text(
        formatCatalogUrl(catalog.rootUrl),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: () => context.push(
        '/browse?catalogId=${catalog.id}&url=${Uri.encodeComponent(catalog.rootUrl.toString())}',
      ),
      trailing: _RowMenu<_CatalogMenuAction>(
        onSelected: (action) => _onMenuAction(context, ref, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _CatalogMenuAction.edit, child: Text('Edit')),
          PopupMenuItem(
            value: _CatalogMenuAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onMenuAction(
    BuildContext context,
    WidgetRef ref,
    _CatalogMenuAction action,
  ) {
    switch (action) {
      case _CatalogMenuAction.edit:
        showDialog<void>(
          context: context,
          builder: (_) => AddEditCatalogDialog(catalog: catalog),
        );
      case _CatalogMenuAction.delete:
        showDialog<void>(
          context: context,
          builder: (_) => _DeleteCatalogDialog(catalog: catalog),
        );
    }
  }
}

enum _CatalogMenuAction { edit, delete }

class _FavoriteRow extends ConsumerWidget {
  final Favorite favorite;
  final List<Catalog> catalogs;

  const _FavoriteRow({required this.favorite, required this.catalogs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final parentTitle =
        catalogs
            .where((c) => c.id == favorite.catalogId)
            .map((c) => c.title)
            .firstOrNull ??
        '';

    return _Row(
      key: Key('favorite-${favorite.id}'),
      mark: _Mark(
        background: scheme.primaryContainer,
        border: appPaletteOf(context).favoriteMarkBorder,
        child: Text(
          _initial(favorite.title),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: favorite.title,
      subtitle: Text(
        parentTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: () => context.push(
        '/browse?catalogId=${favorite.catalogId}&url=${Uri.encodeComponent(favorite.url.toString())}',
      ),
      trailing: _RowMenu<String>(
        onSelected: (_) async {
          await ref.read(favoritesProvider.notifier).remove(favorite.id);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'remove', child: Text('Remove from favourites')),
        ],
      ),
    );
  }
}

/// The letter a favourite is marked with — its first character, uppercased.
String _initial(String title) {
  final trimmed = title.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

class _DeleteCatalogDialog extends ConsumerWidget {
  final Catalog catalog;
  const _DeleteCatalogDialog({required this.catalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Delete catalogue?'),
      content: const Text(
        'This will also remove its favourites and cached feeds.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            await ref.read(catalogsProvider.notifier).delete(catalog.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

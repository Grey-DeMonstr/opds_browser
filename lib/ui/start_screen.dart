import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/widgets/add_edit_catalog_dialog.dart';

class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogsAsync = ref.watch(catalogsProvider);
    final favoritesAsync = ref.watch(favoritesProvider);

    return catalogsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (catalogs) => favoritesAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Error: $e')),
        ),
        data: (favorites) => _StartScreenContent(
          catalogs: catalogs,
          favorites: favorites,
        ),
      ),
    );
  }
}

class _StartScreenContent extends ConsumerWidget {
  final List<Catalog> catalogs;
  final List<Favorite> favorites;

  const _StartScreenContent({
    required this.catalogs,
    required this.favorites,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPDS Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const AddEditCatalogDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add catalogue'),
      ),
      body: CustomScrollView(
        slivers: [
          if (favorites.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Favourites',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _FavoriteTile(favorite: favorites[index], catalogs: catalogs),
                childCount: favorites.length,
              ),
            ),
          ],
          if (catalogs.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Catalogues',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (catalogs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No catalogues yet. Tap + to add one.'),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CatalogTile(catalog: catalogs[index]),
                childCount: catalogs.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogTile extends ConsumerWidget {
  final Catalog catalog;
  const _CatalogTile({required this.catalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(catalog.title),
      subtitle: Text(
        catalog.rootUrl.toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.go(
        '/browse?catalogId=${catalog.id}&url=${Uri.encodeComponent(catalog.rootUrl.toString())}',
      ),
      trailing: PopupMenuButton<_CatalogMenuAction>(
        onSelected: (action) => _onMenuAction(context, ref, action),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _CatalogMenuAction.edit,
            child: Text('Edit'),
          ),
          PopupMenuItem(
            value: _CatalogMenuAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onMenuAction(
      BuildContext context, WidgetRef ref, _CatalogMenuAction action) {
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

class _FavoriteTile extends ConsumerWidget {
  final Favorite favorite;
  final List<Catalog> catalogs;

  const _FavoriteTile({required this.favorite, required this.catalogs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentTitle = catalogs
        .where((c) => c.id == favorite.catalogId)
        .map((c) => c.title)
        .firstOrNull ?? '';

    return ListTile(
      title: Text(favorite.title),
      subtitle: Text(parentTitle),
      onTap: () => context.go(
        '/browse?catalogId=${favorite.catalogId}&url=${Uri.encodeComponent(favorite.url.toString())}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (_) async {
          await ref.read(favoritesProvider.notifier).remove(favorite.id);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'remove',
            child: Text('Remove from favourites'),
          ),
        ],
      ),
    );
  }
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

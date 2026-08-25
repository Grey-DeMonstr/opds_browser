import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeCatalogRepository implements CatalogRepository {
  final List<Catalog> _data;
  var _nextId = 1;

  FakeCatalogRepository({List<Catalog> initial = const []})
    : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId = initial.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Catalog>> getAll() async => List.unmodifiable(_data);

  @override
  Future<Catalog> add(String title, Uri rootUrl) async {
    final c = Catalog(
      id: _nextId++,
      title: title,
      rootUrl: rootUrl,
      protocol: 'opds1',
    );
    _data.add(c);
    return c;
  }

  @override
  Future<void> update(Catalog catalog) async {
    final i = _data.indexWhere((c) => c.id == catalog.id);
    if (i >= 0) _data[i] = catalog;
  }

  @override
  Future<void> delete(int catalogId) async {
    _data.removeWhere((c) => c.id == catalogId);
  }
}

class FakeFavoritesRepository implements FavoritesRepository {
  @override
  Future<List<Favorite>> getAll() async => const [];

  @override
  Future<void> add(int catalogId, Uri url, String title) async {}

  @override
  Future<void> remove(int favoriteId) async {}

  @override
  Future<bool> isFavorite(int catalogId, Uri url) async => false;
}

ProviderContainer makeContainer({List<Catalog> initial = const []}) {
  final container = ProviderContainer(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(initial: initial),
      ),
      // Deleting a catalogue reloads the favourites, so they need a repository
      // even in tests that are only interested in the catalogues.
      favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
    ],
  );
  return container;
}

void main() {
  test('build() loads catalogs from repository', () async {
    final seed = Catalog(
      id: 1,
      title: 'A',
      rootUrl: Uri.parse('https://a.com'),
      protocol: 'opds1',
    );
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    final catalogs = await container.read(catalogsProvider.future);
    expect(catalogs, hasLength(1));
    expect(catalogs.first.title, 'A');
  });

  test('add() inserts catalog and refreshes state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(catalogsProvider.future); // wait for build
    await container
        .read(catalogsProvider.notifier)
        .add('B', Uri.parse('https://b.com'));

    final catalogs = container.read(catalogsProvider).value!;
    expect(catalogs, hasLength(1));
    expect(catalogs.first.title, 'B');
  });

  test('updateCatalog() changes title and refreshes state', () async {
    final seed = Catalog(
      id: 1,
      title: 'Old',
      rootUrl: Uri.parse('https://a.com'),
      protocol: 'opds1',
    );
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(catalogsProvider.future);
    final updated = Catalog(
      id: 1,
      title: 'New',
      rootUrl: Uri.parse('https://a.com'),
      protocol: 'opds1',
    );
    await container.read(catalogsProvider.notifier).updateCatalog(updated);

    final catalogs = container.read(catalogsProvider).value!;
    expect(catalogs.first.title, 'New');
  });

  test('delete() removes catalog and refreshes state', () async {
    final seed = Catalog(
      id: 1,
      title: 'A',
      rootUrl: Uri.parse('https://a.com'),
      protocol: 'opds1',
    );
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(catalogsProvider.future);
    await container.read(catalogsProvider.notifier).delete(1);

    final catalogs = container.read(catalogsProvider).value!;
    expect(catalogs, isEmpty);
  });

  _deleteTests();
}

// ── Deleting a catalogue ──────────────────────────────────────────────────────
//
// The database drops a catalogue's favourites with it (ON DELETE CASCADE), so
// these tests run against a real one rather than a fake that would have to
// imitate the cascade.

ProviderContainer _makeDbContainer() {
  final db = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    seedDefaultCatalogs: false,
  );
  addTearDown(db.close);
  return ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
}

void _deleteTests() {
  test('delete() drops the deleted catalogue favourites', () async {
    final container = _makeDbContainer();
    addTearDown(container.dispose);

    final catalogRepo = container.read(catalogRepositoryProvider);
    final kept = await catalogRepo.add('Keep', Uri.parse('https://keep.com'));
    final doomed = await catalogRepo.add(
      'Doomed',
      Uri.parse('https://doomed.com'),
    );
    final favoritesRepo = container.read(favoritesRepositoryProvider);
    await favoritesRepo.add(kept.id, Uri.parse('https://keep.com/f'), 'Kept');
    await favoritesRepo.add(
      doomed.id,
      Uri.parse('https://doomed.com/f'),
      'Doomed',
    );

    await container.read(catalogsProvider.future);
    await container.read(favoritesProvider.future);

    await container.read(catalogsProvider.notifier).delete(doomed.id);

    final favorites = container.read(favoritesProvider).value!;
    expect(favorites.map((f) => f.title), ['Kept']);
  });
}

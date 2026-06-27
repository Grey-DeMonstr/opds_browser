import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

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

ProviderContainer makeContainer({List<Catalog> initial = const []}) {
  final container = ProviderContainer(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(initial: initial),
      ),
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
}

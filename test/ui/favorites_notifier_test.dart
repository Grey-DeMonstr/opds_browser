import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

class FakeFavoritesRepository implements FavoritesRepository {
  final List<Favorite> _data;
  var _nextId = 1;

  FakeFavoritesRepository({List<Favorite> initial = const []})
      : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId =
          initial.map((f) => f.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Favorite>> getAll() async => List.unmodifiable(_data);

  @override
  Future<void> add(int catalogId, Uri url, String title) async {
    _data.add(Favorite(
      id: _nextId++,
      catalogId: catalogId,
      url: url,
      title: title,
      sortOrder: _data.length,
    ));
  }

  @override
  Future<void> remove(int favoriteId) async {
    _data.removeWhere((f) => f.id == favoriteId);
  }

  @override
  Future<bool> isFavorite(int catalogId, Uri url) async =>
      _data.any((f) => f.catalogId == catalogId && f.url == url);
}

ProviderContainer makeContainer({List<Favorite> initial = const []}) {
  return ProviderContainer(overrides: [
    favoritesRepositoryProvider.overrideWithValue(
      FakeFavoritesRepository(initial: initial),
    ),
  ]);
}

void main() {
  test('build() loads favorites from repository', () async {
    final seed = Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://a.com/feed'),
        title: 'Science',
        sortOrder: 0);
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    final favorites = await container.read(favoritesProvider.future);
    expect(favorites, hasLength(1));
    expect(favorites.first.title, 'Science');
  });

  test('remove() deletes favorite and refreshes state', () async {
    final seed = Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://a.com/feed'),
        title: 'Science',
        sortOrder: 0);
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(favoritesProvider.future);
    await container.read(favoritesProvider.notifier).remove(1);

    final favorites = container.read(favoritesProvider).value!;
    expect(favorites, isEmpty);
  });
}

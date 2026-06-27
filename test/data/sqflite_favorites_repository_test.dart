import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/sqflite_favorites_repository.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  late AppDatabase db;
  late SqfliteFavoritesRepository repo;
  late int catalogId;

  setUp(() async {
    db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = SqfliteFavoritesRepository(db);
    final d = await db.database;
    catalogId = await d.insert('catalogs', {
      'title': 'Test Catalog',
      'root_url': 'https://example.com',
      'protocol': 'opds1',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  });
  tearDown(() => db.close());

  final url = Uri.parse('https://example.com/feed');
  const title = 'My Feed';

  group('SqfliteFavoritesRepository', () {
    test('getAll returns empty list initially', () async {
      expect(await repo.getAll(), isEmpty);
    });

    test('isFavorite returns false before add', () async {
      expect(await repo.isFavorite(catalogId, url), isFalse);
    });

    test('add then isFavorite returns true', () async {
      await repo.add(catalogId, url, title);
      expect(await repo.isFavorite(catalogId, url), isTrue);
    });

    test('add stores title, catalogId, url, and sortOrder', () async {
      await repo.add(catalogId, url, title);
      final all = await repo.getAll();
      expect(all.single.title, title);
      expect(all.single.catalogId, catalogId);
      expect(all.single.url, url);
      expect(all.single.sortOrder, 0); // first insert gets sort_order 0
    });

    test('duplicate add is a no-op — count stays 1', () async {
      await repo.add(catalogId, url, title);
      await repo.add(catalogId, url, title);
      expect(await repo.getAll(), hasLength(1));
    });

    test('remove then isFavorite returns false', () async {
      await repo.add(catalogId, url, title);
      final fav = (await repo.getAll()).single;
      await repo.remove(fav.id);
      expect(await repo.isFavorite(catalogId, url), isFalse);
    });

    test('getAll returns rows in ascending sort_order', () async {
      await repo.add(catalogId, Uri.parse('https://example.com/a'), 'First');
      await repo.add(catalogId, Uri.parse('https://example.com/b'), 'Second');
      await repo.add(catalogId, Uri.parse('https://example.com/c'), 'Third');
      final all = await repo.getAll();
      expect(all.map((Favorite f) => f.title).toList(), [
        'First',
        'Second',
        'Third',
      ]);
    });

    test('sort_order starts at 0 and increments per add', () async {
      await repo.add(catalogId, Uri.parse('https://example.com/a'), 'A');
      await repo.add(catalogId, Uri.parse('https://example.com/b'), 'B');
      final all = await repo.getAll();
      expect(all[0].sortOrder, 0);
      expect(all[1].sortOrder, 1);
    });
  });
}

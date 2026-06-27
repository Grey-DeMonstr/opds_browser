import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/sqflite_catalog_repository.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  late AppDatabase db;
  late SqfliteCatalogRepository repo;

  setUp(() {
    db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = SqfliteCatalogRepository(db);
  });
  tearDown(() => db.close());

  group('SqfliteCatalogRepository', () {
    test('getAll returns empty list initially', () async {
      expect(await repo.getAll(), isEmpty);
    });

    test('add returns Catalog with assigned id', () async {
      final cat = await repo.add(
        'My Catalog',
        Uri.parse('https://example.com/opds'),
      );
      expect(cat.id, isPositive);
      expect(cat.title, 'My Catalog');
      expect(cat.rootUrl, Uri.parse('https://example.com/opds'));
      expect(cat.protocol, 'opds1');
    });

    test('add multiple — getAll returns them in insertion order', () async {
      await repo.add('First', Uri.parse('https://first.com'));
      await repo.add('Second', Uri.parse('https://second.com'));
      final all = await repo.getAll();
      expect(all.length, 2);
      expect(all[0].title, 'First');
      expect(all[1].title, 'Second');
    });

    test('update persists title and rootUrl', () async {
      final cat = await repo.add('Original', Uri.parse('https://original.com'));
      await repo.update(
        Catalog(
          id: cat.id,
          title: 'Updated',
          rootUrl: Uri.parse('https://updated.com'),
          protocol: cat.protocol,
        ),
      );
      final all = await repo.getAll();
      expect(all.single.title, 'Updated');
      expect(all.single.rootUrl, Uri.parse('https://updated.com'));
    });

    test('update does not change protocol', () async {
      final cat = await repo.add('Test', Uri.parse('https://example.com'));
      await repo.update(
        Catalog(
          id: cat.id,
          title: 'Test',
          rootUrl: Uri.parse('https://example.com'),
          protocol: 'opds2', // ignored by the implementation
        ),
      );
      final all = await repo.getAll();
      expect(all.single.protocol, 'opds1');
    });

    test('delete removes the catalog', () async {
      final cat = await repo.add('ToDelete', Uri.parse('https://delete.me'));
      await repo.delete(cat.id);
      expect(await repo.getAll(), isEmpty);
    });

    test('delete cascades to favorites', () async {
      final cat = await repo.add('Parent', Uri.parse('https://parent.com'));
      final d = await db.database;
      await d.insert('favorites', {
        'catalog_id': cat.id,
        'url': 'https://parent.com/feed',
        'title': 'Feed',
        'sort_order': 0,
      });
      await repo.delete(cat.id);
      expect(await d.query('favorites'), isEmpty);
    });

    test('delete of non-existent id is a no-op', () async {
      await repo.add('Keep', Uri.parse('https://keep.com'));
      await repo.delete(9999);
      expect(await repo.getAll(), hasLength(1));
    });
  });
}

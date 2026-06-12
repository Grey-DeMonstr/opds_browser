import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  group('AppDatabase schema', () {
    Future<List<Map<String, Object?>>> tables(Database d) =>
        d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");

    test('catalogs table exists after open', () async {
      final d = await db.database;
      final names = (await tables(d)).map((r) => r['name']).toList();
      expect(names, contains('catalogs'));
    });

    test('feed_cache table exists after open', () async {
      final d = await db.database;
      final names = (await tables(d)).map((r) => r['name']).toList();
      expect(names, contains('feed_cache'));
    });

    test('favorites table exists after open', () async {
      final d = await db.database;
      final names = (await tables(d)).map((r) => r['name']).toList();
      expect(names, contains('favorites'));
    });

    test('foreign keys enforced — insert invalid catalog_id throws', () async {
      final d = await db.database;
      expect(
        () async => d.insert('favorites', {
          'catalog_id': 9999,
          'url': 'https://example.com',
          'title': 'Bad',
          'sort_order': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('cascade: deleting catalog removes its favorites', () async {
      final d = await db.database;
      final catId = await d.insert('catalogs', {
        'title': 'Test',
        'root_url': 'https://example.com',
        'protocol': 'opds1',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await d.insert('favorites', {
        'catalog_id': catId,
        'url': 'https://example.com/feed',
        'title': 'Feed',
        'sort_order': 0,
      });
      await d.delete('catalogs', where: 'id = ?', whereArgs: [catId]);
      final favs = await d.query('favorites');
      expect(favs, isEmpty);
    });
  });
}

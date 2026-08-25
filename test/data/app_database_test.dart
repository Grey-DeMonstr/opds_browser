import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/domain/default_catalogs.dart';

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

    test('local_book_cache table exists after open', () async {
      final d = await db.database;
      final names = (await tables(d)).map((r) => r['name']).toList();
      expect(names, contains('local_book_cache'));
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

  group('AppDatabase default catalogues', () {
    test('a fresh database is seeded with every default catalogue', () async {
      final d = await db.database;
      final rows = await d.query('catalogs', orderBy: 'id ASC');
      expect(rows.map((r) => r['title']), defaultCatalogs.map((c) => c.title));
      expect(
        rows.map((r) => r['root_url']),
        defaultCatalogs.map((c) => c.rootUrl),
      );
    });

    test('seeded catalogues use the opds1 protocol', () async {
      final d = await db.database;
      final rows = await d.query('catalogs');
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row['protocol'], 'opds1');
        expect(row['created_at'], isA<int>());
      }
    });

    test('seeding is skipped when disabled', () async {
      final bare = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        seedDefaultCatalogs: false,
      );
      addTearDown(bare.close);
      final d = await bare.database;
      expect(await d.query('catalogs'), isEmpty);
    });

    test('seeding does not run again when an existing database is '
        'reopened', () async {
      final dir = Directory.systemTemp.createTempSync('opds_seed_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = join(dir.path, 'seed.db');

      final first = AppDatabase(factory: databaseFactoryFfi, path: path);
      final seeded = (await (await first.database).query('catalogs')).length;
      await first.close();

      final second = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(second.close);
      final rows = await (await second.database).query('catalogs');
      expect(rows, hasLength(seeded));
    });
  });
}

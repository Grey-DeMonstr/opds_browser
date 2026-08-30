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

  group('AppDatabase upgrade from v2', () {
    /// Builds a database as version 2 left it: the schema without the feed
    /// entry fields the book page needs, holding one cached feed.
    Future<String> makeV2Database() async {
      final dir = Directory.systemTemp.createTempSync('opds_v2_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = join(dir.path, 'v2.db');

      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) async {
            await d.execute('''
              CREATE TABLE catalogs (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                title      TEXT    NOT NULL,
                root_url   TEXT    NOT NULL,
                protocol   TEXT    NOT NULL DEFAULT 'opds1',
                created_at INTEGER NOT NULL
              )
            ''');
            await d.execute('''
              CREATE TABLE feed_cache (
                catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
                url        TEXT    NOT NULL,
                feed_json  TEXT    NOT NULL,
                fetched_at INTEGER NOT NULL,
                PRIMARY KEY (catalog_id, url)
              )
            ''');
          },
        ),
      );
      final catalogId = await db.insert('catalogs', {
        'title': 'Existing',
        'root_url': 'https://example.com/opds',
        'protocol': 'opds1',
        'created_at': 0,
      });
      await db.insert('feed_cache', {
        'catalog_id': catalogId,
        'url': 'https://example.com/opds',
        'feed_json': '{"title":"stale","entries":[]}',
        'fetched_at': 0,
      });
      await db.close();
      return path;
    }

    test('feeds cached before the upgrade are dropped', () async {
      final path = await makeV2Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      // Entries cached by v2 carry no categories and no content markup, so a
      // book page built from them would be silently bare. Dropping them costs
      // one re-fetch and is invisible.
      expect(await (await db.database).query('feed_cache'), isEmpty);
    });

    test('the upgrade keeps the catalogues the user added', () async {
      final path = await makeV2Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      final rows = await (await db.database).query('catalogs');
      expect(rows.map((r) => r['title']), ['Existing']);
    });

    test('the upgrade does not seed the default catalogues', () async {
      final path = await makeV2Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      final rows = await (await db.database).query('catalogs');
      expect(rows.map((r) => r['title']), isNot(contains('Project Gutenberg')));
    });
  });

  group('AppDatabase upgrade from v3', () {
    /// Builds a database as version 3 left it: the current schema, holding one
    /// cached feed written before search links were kept.
    Future<String> makeV3Database() async {
      final dir = Directory.systemTemp.createTempSync('opds_v3_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = join(dir.path, 'v3.db');

      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (d, _) async {
            await d.execute('''
              CREATE TABLE catalogs (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                title      TEXT    NOT NULL,
                root_url   TEXT    NOT NULL,
                protocol   TEXT    NOT NULL DEFAULT 'opds1',
                created_at INTEGER NOT NULL
              )
            ''');
            await d.execute('''
              CREATE TABLE feed_cache (
                catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
                url        TEXT    NOT NULL,
                feed_json  TEXT    NOT NULL,
                fetched_at INTEGER NOT NULL,
                PRIMARY KEY (catalog_id, url)
              )
            ''');
          },
        ),
      );
      final catalogId = await db.insert('catalogs', {
        'title': 'Existing',
        'root_url': 'https://example.com/opds',
        'protocol': 'opds1',
        'created_at': 0,
      });
      await db.insert('feed_cache', {
        'catalog_id': catalogId,
        'url': 'https://example.com/opds',
        'feed_json': '{"title":"stale","entries":[]}',
        'fetched_at': 0,
      });
      await db.close();
      return path;
    }

    test('roots cached before the upgrade are dropped', () async {
      final path = await makeV3Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      // A root cached by v3 carries no search links, and nothing in the row
      // says so — the catalogue would look unsearchable until something else
      // happened to refresh it.
      expect(await (await db.database).query('feed_cache'), isEmpty);
    });

    test('the upgrade keeps the catalogues the user added', () async {
      final path = await makeV3Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      final rows = await (await db.database).query('catalogs');
      expect(rows.map((r) => r['title']), ['Existing']);
    });
  });
  group('AppDatabase upgrade from v4', () {
    /// Builds a database as version 4 left it, holding a root cached by the
    /// build whose page merge dropped search links.
    Future<String> makeV4Database() async {
      final dir = Directory.systemTemp.createTempSync('opds_v4_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = join(dir.path, 'v4.db');

      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (d, _) async {
            await d.execute('''
              CREATE TABLE catalogs (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                title      TEXT    NOT NULL,
                root_url   TEXT    NOT NULL,
                protocol   TEXT    NOT NULL DEFAULT 'opds1',
                created_at INTEGER NOT NULL
              )
            ''');
            await d.execute('''
              CREATE TABLE feed_cache (
                catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
                url        TEXT    NOT NULL,
                feed_json  TEXT    NOT NULL,
                fetched_at INTEGER NOT NULL,
                PRIMARY KEY (catalog_id, url)
              )
            ''');
          },
        ),
      );
      final catalogId = await db.insert('catalogs', {
        'title': 'Existing',
        'root_url': 'https://example.com/opds',
        'protocol': 'opds1',
        'created_at': 0,
      });
      await db.insert('feed_cache', {
        'catalog_id': catalogId,
        'url': 'https://example.com/opds',
        'feed_json': '{"title":"Root","entries":[]}',
        'fetched_at': 0,
      });
      await db.close();
      return path;
    }

    test('roots cached without their search links are dropped', () async {
      final path = await makeV4Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      // The merge that built these rows discarded the links, so a root cached
      // by that build claims the catalogue cannot be searched. Cache-forever
      // means nothing would ever correct it.
      expect(await (await db.database).query('feed_cache'), isEmpty);
    });

    test('the upgrade keeps the catalogues the user added', () async {
      final path = await makeV4Database();
      final db = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(db.close);

      final rows = await (await db.database).query('catalogs');
      expect(rows.map((r) => r['title']), ['Existing']);
    });
  });
}

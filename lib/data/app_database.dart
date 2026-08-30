import 'package:opds_browser/domain/default_catalogs.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  final DatabaseFactory _factory;
  final String? _path;
  final bool _seedDefaultCatalogs;
  Database? _db;

  /// The parameters are named publicly ('path', not '_path') to match the API
  /// contract, so they cannot be initializing formals for the private fields.
  AppDatabase({
    DatabaseFactory? factory,
    String? path,
    bool seedDefaultCatalogs = true,
  }) : _factory = factory ?? databaseFactory,
       // ignore: prefer_initializing_formals
       _path = path,
       // ignore: prefer_initializing_formals
       _seedDefaultCatalogs = seedDefaultCatalogs;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = _path ?? join(await getDatabasesPath(), 'opds_browser.db');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await _createV1Schema(db);
          await _createV2Schema(db);
          if (_seedDefaultCatalogs) await _seedCatalogs(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createV2Schema(db);
          // v3 widened what a cached entry holds — categories and the
          // description's own markup. Rows written by v2 carry neither, and
          // nothing in them says so, so a book page built from one would be
          // quietly bare. They cost a single re-fetch to replace.
          if (oldVersion < 3) await db.delete('feed_cache');
          // v4 widened it again — a feed now carries the search links it
          // advertises. A root cached by v3 has none, and nothing in the row
          // says whether that means "not searchable" or "written before we
          // looked", so the catalogue would look unsearchable until something
          // else refreshed it.
          if (oldVersion < 4) await db.delete('feed_cache');
          // v5 discards them again, for a bug rather than a new field: the
          // page merge that wrote these rows dropped the search links off the
          // feed it rebuilt. A root cached by that build says the catalogue
          // cannot be searched, and cache-forever means nothing would ever
          // ask again.
          if (oldVersion < 5) await db.delete('feed_cache');
        },
      ),
    );
  }

  Future<void> _createV1Schema(Database db) async {
    await db.execute('''
      CREATE TABLE catalogs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT    NOT NULL,
        root_url   TEXT    NOT NULL,
        protocol   TEXT    NOT NULL DEFAULT 'opds1',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE feed_cache (
        catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
        url        TEXT    NOT NULL,
        feed_json  TEXT    NOT NULL,
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (catalog_id, url)
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
        url        TEXT    NOT NULL,
        title      TEXT    NOT NULL,
        sort_order INTEGER NOT NULL,
        UNIQUE (catalog_id, url)
      )
    ''');
  }

  Future<void> _createV2Schema(Database db) async {
    await db.execute('''
      CREATE TABLE local_book_cache (
        path         TEXT    PRIMARY KEY,
        title        TEXT    NOT NULL,
        author       TEXT    NOT NULL,
        series       TEXT,
        series_index INTEGER
      )
    ''');
  }

  /// Fills a brand-new catalogues table with the built-in examples. Only ever
  /// called from `onCreate`, so an install that already has a database keeps
  /// whatever the user curated there.
  Future<void> _seedCatalogs(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final catalog in defaultCatalogs) {
      batch.insert('catalogs', {
        'title': catalog.title,
        'root_url': catalog.rootUrl,
        'protocol': 'opds1',
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  final DatabaseFactory _factory;
  final String? _path;
  Database? _db;

  /// The parameter is named 'path' (public) not '_path' (private) to match the API contract.
  // ignore: prefer_initializing_formals
  AppDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory ?? databaseFactory,
      // ignore: prefer_initializing_formals
      _path = path;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = _path ?? join(await getDatabasesPath(), 'opds_browser.db');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await _createV1Schema(db);
          await _createV2Schema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createV2Schema(db);
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

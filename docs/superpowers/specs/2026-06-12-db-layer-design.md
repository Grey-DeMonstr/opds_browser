# DB Layer + Repositories — Design Spec

**Date:** 2026-06-12
**Step:** 4 of 11 (spec §14)
**Status:** Approved

---

## Goal

Implement the persistence layer: the sqflite database singleton, and concrete implementations of `CatalogRepository`, `FavoritesRepository`, and `SettingsRepository`. All tests run on the host (no device, no emulator) using `sqflite_common_ffi` and `SharedPreferences.setMockInitialValues`.

`FeedRepository` is **not** in this step — it is step 5. The `feed_cache` table is created here (part of the single DB schema) but no code uses it until step 5.

---

## File Structure

```
lib/data/
  app_database.dart                       # AppDatabase — opens DB, schema v1, PRAGMA
  sqflite_catalog_repository.dart         # SqfliteCatalogRepository
  sqflite_favorites_repository.dart       # SqfliteFavoritesRepository
  shared_prefs_settings_repository.dart   # SharedPrefsSettingsRepository

test/data/
  app_database_test.dart                  # schema, PRAGMA, cascade
  sqflite_catalog_repository_test.dart    # CRUD, ordering, cascade verification
  sqflite_favorites_repository_test.dart  # add/remove/isFavorite, uniqueness, ordering
  shared_prefs_settings_repository_test.dart  # defaults, roundtrip, booleans
```

No DAO sub-layer. The repository classes are the thin DAOs — each is 3–5 SQL statements and a row-mapper.

---

## AppDatabase (`lib/data/app_database.dart`)

Constructor accepts an optional `DatabaseFactory`; production code passes nothing (falls back to `databaseFactory`, sqflite's default). Tests pass `databaseFactoryFfi`.

```dart
class AppDatabase {
  final DatabaseFactory _factory;
  final String? _path;   // null → use getDatabasesPath(); tests pass inMemoryDatabasePath
  Database? _db;

  AppDatabase({DatabaseFactory? factory, String? path})
      : _factory = factory ?? databaseFactory,
        _path = path;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = _path ?? join(await getDatabasesPath(), 'opds_browser.db');
    return _factory.openDatabase(
      path,
      onCreate: (db, _) => _createSchema(db),
      onOpen:   (db)    => db.execute('PRAGMA foreign_keys = ON'),
      version: 1,
    );
  }

  Future<void> close() async => (await database).close();
}
```

`PRAGMA foreign_keys = ON` is set in `onOpen` (not `onCreate`) so it applies on every connection, not just the first time the DB is created.

### Schema (version 1)

Created in `_createSchema` via `db.execute` calls, one per table. Exact SQL from spec §6:

```sql
CREATE TABLE catalogs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  title      TEXT    NOT NULL,
  root_url   TEXT    NOT NULL,
  protocol   TEXT    NOT NULL DEFAULT 'opds1',
  created_at INTEGER NOT NULL
);

CREATE TABLE feed_cache (
  catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
  url        TEXT    NOT NULL,
  feed_json  TEXT    NOT NULL,
  fetched_at INTEGER NOT NULL,
  PRIMARY KEY (catalog_id, url)
);

CREATE TABLE favorites (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
  url        TEXT    NOT NULL,
  title      TEXT    NOT NULL,
  sort_order INTEGER NOT NULL,
  UNIQUE (catalog_id, url)
);
```

---

## SqfliteCatalogRepository (`lib/data/sqflite_catalog_repository.dart`)

```dart
class SqfliteCatalogRepository implements CatalogRepository {
  final AppDatabase _db;
  SqfliteCatalogRepository(this._db);
}
```

### Method contracts

| Method | SQL | Notes |
|---|---|---|
| `getAll()` | `SELECT * FROM catalogs ORDER BY id ASC` | Stable insertion order |
| `add(title, rootUrl)` | `INSERT INTO catalogs ...` | `created_at` = `DateTime.now().millisecondsSinceEpoch`; returns `Catalog` with assigned `id` |
| `update(catalog)` | `UPDATE catalogs SET title=?, root_url=? WHERE id=?` | `protocol` is not user-editable; `created_at` is not changed |
| `delete(catalogId)` | `DELETE FROM catalogs WHERE id=?` | FK cascade removes `feed_cache` and `favorites` rows automatically |

Row mapper (`_fromRow`):
```dart
Catalog _fromRow(Map<String, Object?> row) => Catalog(
  id:       row['id']       as int,
  title:    row['title']    as String,
  rootUrl:  Uri.parse(row['root_url'] as String),
  protocol: row['protocol'] as String,
);
```

---

## SqfliteFavoritesRepository (`lib/data/sqflite_favorites_repository.dart`)

```dart
class SqfliteFavoritesRepository implements FavoritesRepository {
  final AppDatabase _db;
  SqfliteFavoritesRepository(this._db);
}
```

### Method contracts

| Method | SQL | Notes |
|---|---|---|
| `getAll()` | `SELECT * FROM favorites ORDER BY sort_order ASC` | |
| `add(catalogId, url, title)` | `INSERT OR IGNORE INTO favorites ...` | `sort_order` = `SELECT COALESCE(MAX(sort_order)+1, 0) FROM favorites`; duplicate `(catalogId, url)` is silently ignored |
| `remove(favoriteId)` | `DELETE FROM favorites WHERE id=?` | |
| `isFavorite(catalogId, url)` | `SELECT COUNT(*) FROM favorites WHERE catalog_id=? AND url=?` | Returns `count > 0` |

`url` is stored as its string representation (`uri.toString()`). No normalization at this layer — `FeedRepository` handles URL normalization for cache keys in step 5.

Row mapper (`_fromRow`):
```dart
Favorite _fromRow(Map<String, Object?> row) => Favorite(
  id:        row['id']         as int,
  catalogId: row['catalog_id'] as int,
  url:       Uri.parse(row['url'] as String),
  title:     row['title']      as String,
  sortOrder: row['sort_order'] as int,
);
```

---

## SharedPrefsSettingsRepository (`lib/data/shared_prefs_settings_repository.dart`)

```dart
class SharedPrefsSettingsRepository implements SettingsRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
}
```

### Key mapping

| Key | Type | Default |
|---|---|---|
| `download_target_kind` | `String` (`"system"` \| `"custom"`) | `"system"` |
| `download_target_uri` | `String?` | absent |
| `folder_per_author` | `bool` | `false` |
| `folder_per_series` | `bool` | `false` |

`load()` reads all four keys; returns `AppSettings` with defaults for any absent key. `save()` writes all four keys atomically (sequentially — `SharedPreferences` has no transaction API, which is acceptable for settings with no concurrent writers).

`DownloadTarget` deserialization: `kind == "custom"` + non-null URI → `CustomSafFolder(uri)`; anything else → `SystemDownloads()`.

---

## Testing Strategy

### sqflite repository tests

Every sqflite test file has:
```dart
setUpAll(() {
  sqfliteGlobalDatabaseFactory = databaseFactoryFfi;
});
```

Each individual test constructs a fresh `AppDatabase`:
```dart
late AppDatabase db;
setUp(() async {
  db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
});
tearDown(() => db.close());
```

In-memory databases are isolated per-test with no file cleanup needed.

### `app_database_test.dart`

- All three tables exist after first open (query `sqlite_master`).
- PRAGMA is ON: inserting a `favorites` row with a non-existent `catalog_id` throws a `DatabaseException`.
- Cascade: inserting a catalog + favorite, then deleting the catalog → favorites table is empty.

### `sqflite_catalog_repository_test.dart`

- `getAll` returns `[]` initially.
- `add` returns a `Catalog` with a positive assigned `id`.
- Two `add` calls → `getAll` returns both in insertion order.
- `update` persists `title` and `rootUrl` changes; `id` and `protocol` are unchanged.
- `delete` removes the catalog; a pre-existing favorite for that catalog is also removed (cascade).
- `delete` of a non-existent `id` is a no-op (no exception).

### `sqflite_favorites_repository_test.dart`

- `getAll` returns `[]` initially.
- `add` then `isFavorite` → `true`.
- `isFavorite` before `add` → `false`.
- Duplicate `add` (same `catalogId` + `url`) is a no-op; `getAll` still returns one row.
- `remove` then `isFavorite` → `false`.
- Multiple adds → `getAll` returns rows in ascending `sort_order` (insertion order).

### `shared_prefs_settings_repository_test.dart`

```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
});
```

- `load()` with no keys set → `AppSettings(target: SystemDownloads(), createAuthorFolder: false, createSeriesFolder: false)`.
- `save` + `load` roundtrip for `SystemDownloads`.
- `save` + `load` roundtrip for `CustomSafFolder('content://some/uri')`.
- Both folder booleans persist correctly when set to `true`.

---

## Constraints

- No `flutter` imports in `lib/data/` except `shared_prefs_settings_repository.dart` (which uses `shared_preferences`, a Flutter plugin).
- `sqflite_catalog_repository.dart` and `sqflite_favorites_repository.dart` are pure Dart + sqflite — no Flutter bindings.
- `dart run tool/check.dart` (analyze + test) must be green before the step is considered done.
- `feed_cache` table is created but has no Dart implementation in this step.

import 'package:sqflite/sqflite.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/domain/local_library.dart';

class SqfliteLocalLibraryCache {
  final AppDatabase _db;
  SqfliteLocalLibraryCache(this._db);

  Future<LocalBookMetadata?> get(String path) async {
    final db = await _db.database;
    final rows = await db.query(
      'local_book_cache',
      where: 'path = ?',
      whereArgs: [path],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> put(String path, LocalBookMetadata meta) async {
    final db = await _db.database;
    await db.insert(
      'local_book_cache',
      _toRow(path, meta),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putAll(Map<String, LocalBookMetadata> entries) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final e in entries.entries) {
        await txn.insert(
          'local_book_cache',
          _toRow(e.key, e.value),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteAll() async {
    final db = await _db.database;
    await db.delete('local_book_cache');
  }

  Map<String, Object?> _toRow(String path, LocalBookMetadata meta) => {
    'path': path,
    'title': meta.title,
    'author': meta.author,
    'series': meta.series,
    'series_index': meta.seriesIndex,
  };

  LocalBookMetadata _fromRow(Map<String, Object?> row) => LocalBookMetadata(
    title: row['title'] as String,
    author: row['author'] as String,
    series: row['series'] as String?,
    seriesIndex: row['series_index'] as int?,
  );
}

import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteFavoritesRepository implements FavoritesRepository {
  final AppDatabase _db;
  SqfliteFavoritesRepository(this._db);

  @override
  Future<List<Favorite>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('favorites', orderBy: 'sort_order ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> add(int catalogId, Uri url, String title) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order) + 1, 0) AS next FROM favorites',
    );
    final nextOrder = (result.first['next'] as num).toInt();
    await db.insert(
      'favorites',
      {
        'catalog_id': catalogId,
        'url': url.toString(),
        'title': title,
        'sort_order': nextOrder,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> remove(int favoriteId) async {
    final db = await _db.database;
    await db.delete('favorites', where: 'id = ?', whereArgs: [favoriteId]);
  }

  @override
  Future<bool> isFavorite(int catalogId, Uri url) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM favorites WHERE catalog_id = ? AND url = ?',
      [catalogId, url.toString()],
    );
    return (result.first['cnt'] as int) > 0;
  }

  Favorite _fromRow(Map<String, Object?> row) => Favorite(
        id: row['id'] as int,
        catalogId: row['catalog_id'] as int,
        url: Uri.parse(row['url'] as String),
        title: row['title'] as String,
        sortOrder: row['sort_order'] as int,
      );
}

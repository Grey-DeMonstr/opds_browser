import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';

class SqfliteCatalogRepository implements CatalogRepository {
  final AppDatabase _db;
  SqfliteCatalogRepository(this._db);

  @override
  Future<List<Catalog>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('catalogs', orderBy: 'id ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Catalog> add(String title, Uri rootUrl) async {
    final db = await _db.database;
    final id = await db.insert('catalogs', {
      'title': title,
      'root_url': rootUrl.toString(),
      'protocol': 'opds1',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return Catalog(id: id, title: title, rootUrl: rootUrl, protocol: 'opds1');
  }

  @override
  Future<void> update(Catalog catalog) async {
    final db = await _db.database;
    await db.update(
      'catalogs',
      {'title': catalog.title, 'root_url': catalog.rootUrl.toString()},
      where: 'id = ?',
      whereArgs: [catalog.id],
    );
  }

  @override
  Future<void> delete(int catalogId) async {
    final db = await _db.database;
    await db.delete('catalogs', where: 'id = ?', whereArgs: [catalogId]);
  }

  Catalog _fromRow(Map<String, Object?> row) => Catalog(
    id: row['id'] as int,
    title: row['title'] as String,
    rootUrl: Uri.parse(row['root_url'] as String),
    protocol: row['protocol'] as String,
  );
}

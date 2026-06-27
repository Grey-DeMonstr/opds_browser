import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
import 'package:opds_browser/domain/local_library.dart';

AppDatabase _makeDb() =>
    AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

const _meta1 = LocalBookMetadata(
  title: 'Book One',
  author: 'Jane Doe',
  series: 'My Series',
  seriesIndex: 1,
);
const _meta2 = LocalBookMetadata(title: 'Book Two', author: 'John Smith');

void main() {
  late AppDatabase db;
  late SqfliteLocalLibraryCache cache;

  setUp(() {
    db = _makeDb();
    cache = SqfliteLocalLibraryCache(db);
  });
  tearDown(() => db.close());

  test('get returns null on cache miss', () async {
    expect(await cache.get('a/b.fb2'), isNull);
  });

  test('put then get returns stored metadata', () async {
    await cache.put('a/b.fb2', _meta1);
    final result = await cache.get('a/b.fb2');
    expect(result?.title, 'Book One');
    expect(result?.author, 'Jane Doe');
    expect(result?.series, 'My Series');
    expect(result?.seriesIndex, 1);
  });

  test('put overwrites existing entry', () async {
    await cache.put('a/b.fb2', _meta1);
    await cache.put('a/b.fb2', _meta2);
    final result = await cache.get('a/b.fb2');
    expect(result?.title, 'Book Two');
    expect(result?.series, isNull);
    expect(result?.seriesIndex, isNull);
  });

  test('putAll stores multiple entries', () async {
    await cache.putAll({'a/1.fb2': _meta1, 'b/2.fb2': _meta2});
    expect((await cache.get('a/1.fb2'))?.title, 'Book One');
    expect((await cache.get('b/2.fb2'))?.title, 'Book Two');
  });

  test('deleteAll empties the table', () async {
    await cache.putAll({'a/1.fb2': _meta1, 'b/2.fb2': _meta2});
    await cache.deleteAll();
    expect(await cache.get('a/1.fb2'), isNull);
    expect(await cache.get('b/2.fb2'), isNull);
  });

  test('null series_index round-trips as null', () async {
    await cache.put('c/d.fb2', _meta2);
    final result = await cache.get('c/d.fb2');
    expect(result?.seriesIndex, isNull);
  });
}

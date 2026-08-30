import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/caching_feed_repository.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/domain/opds_search.dart';

/// The whole chain a catalogue root travels: bytes off the wire, the real
/// parser, the real caching repository, real SQL. Every layer was tested on
/// its own while the seam between two of them dropped the search links.
void main() {
  late AppDatabase db;
  late int catalogId;

  setUp(() async {
    db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final d = await db.database;
    catalogId = await d.insert('catalogs', {
      'title': 'Example',
      'root_url': 'https://example.com/opds',
      'protocol': 'opds1',
      'created_at': 0,
    });
  });
  tearDown(() => db.close());

  test('a root advertising search arrives searchable, and stays so', () async {
    final bytes = File('test/fixtures/search_links_root.xml').readAsBytesSync();
    final client = Opds1Client(
      MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    final repo = CachingFeedRepository(db, client);
    final url = Uri.parse('https://example.com/opds');

    final fresh = await repo.getFeed(catalogId, url);
    expect(
      preferredSearchLink(fresh.feed.searchLinks),
      isNotNull,
      reason: 'a freshly fetched root must keep its search links',
    );

    final cached = await repo.getFeed(catalogId, url);
    expect(cached.fromCache, isTrue);
    expect(
      preferredSearchLink(cached.feed.searchLinks),
      isNotNull,
      reason: 'and so must the copy read back out of the cache',
    );
  });
}

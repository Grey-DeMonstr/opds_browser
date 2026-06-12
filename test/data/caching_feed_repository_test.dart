import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/caching_feed_repository.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

class _FakeOpdsClient implements OpdsClient {
  final List<ParsedFeed> _queue;
  int callCount = 0;

  _FakeOpdsClient(this._queue);

  @override
  Future<ParsedFeed> fetchFeed(Uri url) async => _queue[callCount++];

  @override
  Future<bool> probe(Uri url) async => true;
}

void main() {
  late AppDatabase db;
  late int catalogId;

  setUp(() async {
    db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final d = await db.database;
    catalogId = await d.insert('catalogs', {
      'title': 'Test Catalog',
      'root_url': 'https://example.com',
      'protocol': 'opds1',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  });
  tearDown(() => db.close());

  final url = Uri.parse('https://example.com/opds');

  ParsedFeed singlePage(String title) => ParsedFeed(
        title: title,
        entries: [
          NavigationEntry(
            title: 'Item',
            url: Uri.parse('https://example.com/item'),
          ),
        ],
        nextPageUrl: null,
      );

  group('CachingFeedRepository', () {
    test('cache miss — fetches feed, writes to DB, returns fromCache: false', () async {
      final client = _FakeOpdsClient([singlePage('My Feed')]);
      final repo = CachingFeedRepository(db, client);

      final result = await repo.getFeed(catalogId, url);

      expect(result.fromCache, isFalse);
      expect(result.feed.title, 'My Feed');
      expect(client.callCount, 1);

      final d = await db.database;
      expect(await d.query('feed_cache'), hasLength(1));
    });

    test('cache hit — returns stored feed, does not call client again', () async {
      final client = _FakeOpdsClient([singlePage('Cached Feed')]);
      final repo = CachingFeedRepository(db, client);

      await repo.getFeed(catalogId, url);
      final callsAfterFirst = client.callCount;

      final result = await repo.getFeed(catalogId, url);

      expect(result.fromCache, isTrue);
      expect(result.feed.title, 'Cached Feed');
      expect(client.callCount, callsAfterFirst);
    });

    test('cache hit — fetchedAt matches value stored on first fetch', () async {
      final client = _FakeOpdsClient([singlePage('Feed')]);
      final repo = CachingFeedRepository(db, client);

      final first = await repo.getFeed(catalogId, url);
      final second = await repo.getFeed(catalogId, url);

      expect(second.fetchedAt, first.fetchedAt);
    });

    test('fetchedAt on cache miss is within current-time range', () async {
      final client = _FakeOpdsClient([singlePage('Feed')]);
      final repo = CachingFeedRepository(db, client);

      final before = DateTime.now().millisecondsSinceEpoch;
      final result = await repo.getFeed(catalogId, url);
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(
        result.fetchedAt.millisecondsSinceEpoch,
        inInclusiveRange(before, after),
      );
    });

    test('forceRefresh — calls client even when cached, overwrites DB row', () async {
      final client = _FakeOpdsClient([singlePage('Old'), singlePage('New')]);
      final repo = CachingFeedRepository(db, client);

      await repo.getFeed(catalogId, url);
      final result = await repo.getFeed(catalogId, url, forceRefresh: true);

      expect(result.fromCache, isFalse);
      expect(result.feed.title, 'New');

      final d = await db.database;
      final rows = await d.query('feed_cache');
      expect(rows, hasLength(1));
      final stored =
          jsonDecode(rows.first['feed_json'] as String) as Map<String, dynamic>;
      expect(stored['title'], 'New');
    });

    test('normalizeUrl — http://host:80/path and http://host/path share one cache row', () async {
      final client = _FakeOpdsClient([singlePage('Feed')]);
      final repo = CachingFeedRepository(db, client);

      await repo.getFeed(catalogId, Uri.parse('http://example.com:80/opds'));
      final result = await repo.getFeed(catalogId, Uri.parse('http://example.com/opds'));

      expect(result.fromCache, isTrue);
      expect(client.callCount, 1);
    });
  });
}

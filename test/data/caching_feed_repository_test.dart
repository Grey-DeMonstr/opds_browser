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

  group('CachingFeedRepository — pagination', () {
    test('multi-page feed merges all entries; nextPageUrl is null', () async {
      final pages = [
        ParsedFeed(
          title: 'Feed',
          entries: [NavigationEntry(title: 'A', url: Uri.parse('https://example.com/a'))],
          nextPageUrl: Uri.parse('https://example.com/opds?page=2'),
        ),
        ParsedFeed(
          title: 'Feed p2',
          entries: [NavigationEntry(title: 'B', url: Uri.parse('https://example.com/b'))],
          nextPageUrl: Uri.parse('https://example.com/opds?page=3'),
        ),
        ParsedFeed(
          title: 'Feed p3',
          entries: [NavigationEntry(title: 'C', url: Uri.parse('https://example.com/c'))],
          nextPageUrl: null,
        ),
      ];
      final client = _FakeOpdsClient(pages);
      final repo = CachingFeedRepository(db, client);

      final result = await repo.getFeed(catalogId, url);

      expect(result.feed.title, 'Feed');
      expect(result.feed.entries, hasLength(3));
      expect(result.feed.nextPageUrl, isNull);
      expect(client.callCount, 3);
    });

    test('uses first page title when merging', () async {
      final pages = [
        ParsedFeed(
          title: 'Root Title',
          entries: [],
          nextPageUrl: Uri.parse('https://example.com/opds?page=2'),
        ),
        ParsedFeed(title: 'Page 2 Title', entries: [], nextPageUrl: null),
      ];
      final client = _FakeOpdsClient(pages);
      final repo = CachingFeedRepository(db, client);

      final result = await repo.getFeed(catalogId, url);

      expect(result.feed.title, 'Root Title');
    });

    test('stops at 50-page cap; returns 50 entries', () async {
      // 51 pages available; each has 1 entry and a nextPageUrl.
      // The cap check fires after fetching page 50 (pageCount reaches 50).
      final feeds = List.generate(
        51,
        (i) => ParsedFeed(
          title: 'Feed',
          entries: [
            NavigationEntry(title: 'E$i', url: Uri.parse('https://example.com/$i')),
          ],
          nextPageUrl: Uri.parse('https://example.com/opds?page=${i + 2}'),
        ),
      );
      final client = _FakeOpdsClient(feeds);
      final repo = CachingFeedRepository(db, client);

      final result = await repo.getFeed(catalogId, url);

      expect(client.callCount, 50);
      expect(result.feed.entries, hasLength(50));
    });

    test('stops at 5000-entry cap; returns 5000 entries', () async {
      // 26 pages × 200 entries each; cap fires after page 25 (5000 entries total).
      final feeds = List.generate(
        26,
        (i) => ParsedFeed(
          title: 'Feed',
          entries: List.generate(
            200,
            (j) => NavigationEntry(
              title: 'E',
              url: Uri.parse('https://example.com/$i/$j'),
            ),
          ),
          nextPageUrl: Uri.parse('https://example.com/opds?page=${i + 2}'),
        ),
      );
      final client = _FakeOpdsClient(feeds);
      final repo = CachingFeedRepository(db, client);

      final result = await repo.getFeed(catalogId, url);

      expect(client.callCount, 25);
      expect(result.feed.entries, hasLength(5000));
    });
  });
}

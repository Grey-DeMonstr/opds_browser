# FeedRepository — Caching & Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `CachingFeedRepository` — the data-layer class that fulfils the `FeedRepository` interface with sqflite cache-first retrieval, URL normalization, and multi-page feed merging.

**Architecture:** Two new files: `lib/data/url_normalizer.dart` (top-level `normalizeUrl` pure function) and `lib/data/caching_feed_repository.dart` (`CachingFeedRepository` wrapping `AppDatabase` + `OpdsClient`). No existing files are modified. Cache key is `(catalog_id, normalizeUrl(url))`; stored value is `ParsedFeed.toJson()` encoded as a JSON string. Pagination is handled inside a private `_fetchAllPages` method, expanded incrementally via TDD.

**Tech Stack:** `sqflite`, `sqflite_common_ffi` (host tests), `dart:convert`, `flutter_test`

---

### Task 1: `normalizeUrl`

**Files:**
- Create: `lib/data/url_normalizer.dart`
- Create: `test/data/url_normalizer_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/data/url_normalizer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/url_normalizer.dart';

void main() {
  group('normalizeUrl', () {
    test('strips fragment', () {
      expect(normalizeUrl(Uri.parse('http://a.com/p#frag')), 'http://a.com/p');
    });

    test('removes default HTTP port 80', () {
      expect(normalizeUrl(Uri.parse('http://a.com:80/p')), 'http://a.com/p');
    });

    test('removes default HTTPS port 443', () {
      expect(normalizeUrl(Uri.parse('https://a.com:443/p')), 'https://a.com/p');
    });

    test('keeps non-default port', () {
      expect(normalizeUrl(Uri.parse('http://a.com:8080/p')), 'http://a.com:8080/p');
    });

    test('lowercases scheme and host (via Uri.parse)', () {
      expect(normalizeUrl(Uri.parse('http://A.COM/p')), 'http://a.com/p');
    });

    test('preserves query string', () {
      expect(normalizeUrl(Uri.parse('http://a.com/p?q=1')), 'http://a.com/p?q=1');
    });

    test('strips fragment and default port together', () {
      expect(
        normalizeUrl(Uri.parse('https://a.com:443/p?q=1#frag')),
        'https://a.com/p?q=1',
      );
    });
  });
}
```

- [ ] **Step 2: Run tests — expect compilation failure**

```powershell
flutter test test/data/url_normalizer_test.dart
```

Expected: compilation error — `package:opds_browser/data/url_normalizer.dart` does not exist yet.

- [ ] **Step 3: Implement `normalizeUrl`**

Create `lib/data/url_normalizer.dart`:

```dart
String normalizeUrl(Uri url) {
  var u = url.removeFragment();
  if ((u.scheme == 'http' && u.port == 80) ||
      (u.scheme == 'https' && u.port == 443)) {
    u = u.replace(port: 0);
  }
  return u.toString();
}
```

- [ ] **Step 4: Run tests — expect all pass**

```powershell
flutter test test/data/url_normalizer_test.dart
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/url_normalizer.dart test/data/url_normalizer_test.dart
git commit -m "feat(data): add normalizeUrl pure function"
```

---

### Task 2: `CachingFeedRepository` — cache miss, hit, forceRefresh

**Files:**
- Create: `lib/data/caching_feed_repository.dart`
- Create: `test/data/caching_feed_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/data/caching_feed_repository_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests — expect compilation failure**

```powershell
flutter test test/data/caching_feed_repository_test.dart
```

Expected: compilation error — `CachingFeedRepository` does not exist yet.

- [ ] **Step 3: Implement `CachingFeedRepository` with single-page `_fetchAllPages`**

Create `lib/data/caching_feed_repository.dart`:

```dart
import 'dart:convert';

import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:sqflite/sqflite.dart';

class CachingFeedRepository implements FeedRepository {
  final AppDatabase _db;
  final OpdsClient _client;

  CachingFeedRepository(this._db, this._client);

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async {
    final key = normalizeUrl(url);
    final db = await _db.database;

    if (!forceRefresh) {
      final rows = await db.query(
        'feed_cache',
        where: 'catalog_id = ? AND url = ?',
        whereArgs: [catalogId, key],
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        return CachedFeed(
          feed: ParsedFeed.fromJson(
            jsonDecode(row['feed_json'] as String) as Map<String, dynamic>,
          ),
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
          fromCache: true,
        );
      }
    }

    final feed = await _fetchAllPages(url);
    final now = DateTime.now();
    await db.insert(
      'feed_cache',
      {
        'catalog_id': catalogId,
        'url': key,
        'feed_json': jsonEncode(feed.toJson()),
        'fetched_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return CachedFeed(feed: feed, fetchedAt: now, fromCache: false);
  }

  // Minimal implementation: single-page only. Expanded in the next task.
  Future<ParsedFeed> _fetchAllPages(Uri startUrl) async {
    return _client.fetchFeed(startUrl);
  }
}
```

- [ ] **Step 4: Run tests — expect all 6 pass**

```powershell
flutter test test/data/caching_feed_repository_test.dart
```

Expected: 6 tests pass.

- [ ] **Step 5: Run full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/data/caching_feed_repository.dart test/data/caching_feed_repository_test.dart
git commit -m "feat(data): add CachingFeedRepository with cache miss/hit and forceRefresh"
```

---

### Task 3: Pagination merge and safety caps

**Files:**
- Modify: `test/data/caching_feed_repository_test.dart` (add pagination group)
- Modify: `lib/data/caching_feed_repository.dart` (expand `_fetchAllPages`)

- [ ] **Step 1: Add failing pagination tests**

Append the following group inside `main()` in `test/data/caching_feed_repository_test.dart`, after the closing `});` of the existing `group('CachingFeedRepository', ...)`:

```dart
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
```

- [ ] **Step 2: Run new tests — expect failure**

```powershell
flutter test test/data/caching_feed_repository_test.dart
```

Expected: the four new pagination tests fail. The multi-page test fails because `_fetchAllPages` only fetches one page (so `entries` has 1 entry, not 3, and `callCount` is 1, not 3). The title test fails for the same reason. The cap tests fail because only 1 page is fetched.

- [ ] **Step 3: Expand `_fetchAllPages` with full pagination and safety caps**

Replace `lib/data/caching_feed_repository.dart` entirely:

```dart
import 'dart:convert';

import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:sqflite/sqflite.dart';

class CachingFeedRepository implements FeedRepository {
  final AppDatabase _db;
  final OpdsClient _client;

  CachingFeedRepository(this._db, this._client);

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async {
    final key = normalizeUrl(url);
    final db = await _db.database;

    if (!forceRefresh) {
      final rows = await db.query(
        'feed_cache',
        where: 'catalog_id = ? AND url = ?',
        whereArgs: [catalogId, key],
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        return CachedFeed(
          feed: ParsedFeed.fromJson(
            jsonDecode(row['feed_json'] as String) as Map<String, dynamic>,
          ),
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
          fromCache: true,
        );
      }
    }

    final feed = await _fetchAllPages(url);
    final now = DateTime.now();
    await db.insert(
      'feed_cache',
      {
        'catalog_id': catalogId,
        'url': key,
        'feed_json': jsonEncode(feed.toJson()),
        'fetched_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return CachedFeed(feed: feed, fetchedAt: now, fromCache: false);
  }

  Future<ParsedFeed> _fetchAllPages(Uri startUrl) async {
    final allEntries = <FeedEntry>[];
    var title = '';
    var pageUrl = startUrl;
    var pageCount = 0;

    while (true) {
      final feed = await _client.fetchFeed(pageUrl);
      if (pageCount == 0) title = feed.title;
      allEntries.addAll(feed.entries);
      pageCount++;
      if (feed.nextPageUrl == null) break;
      if (pageCount >= 50) break;
      if (allEntries.length >= 5000) break;
      pageUrl = feed.nextPageUrl!;
    }

    return ParsedFeed(title: title, entries: allEntries, nextPageUrl: null);
  }
}
```

- [ ] **Step 4: Run all repository tests — expect all pass**

```powershell
flutter test test/data/caching_feed_repository_test.dart
```

Expected: all 10 tests pass (6 from Task 2 + 4 new pagination tests).

- [ ] **Step 5: Run full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/data/caching_feed_repository.dart test/data/caching_feed_repository_test.dart
git commit -m "feat(data): expand _fetchAllPages with pagination merge and safety caps"
```

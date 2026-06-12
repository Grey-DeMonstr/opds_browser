# FeedRepository with Caching and Pagination — Design Spec

**Date:** 2026-06-12
**Step:** 5 of 11 (spec §14)
**Status:** Approved

---

## Overview

Implements `FeedRepository` (already defined in `lib/domain/repositories.dart`) with cache-first retrieval, URL-keyed sqflite storage, and multi-page feed merging. No progress-reporting mechanism is added at this step — that is a step-7 (BrowseScreen) concern.

---

## New files

```
lib/data/url_normalizer.dart                        # normalizeUrl pure function
lib/data/caching_feed_repository.dart               # CachingFeedRepository
test/data/url_normalizer_test.dart
test/data/caching_feed_repository_test.dart
```

No existing files are modified except adding exports if needed.

---

## `normalizeUrl`

**File:** `lib/data/url_normalizer.dart`

Top-level pure function. Dart's `Uri.parse()` already lowercases scheme and host, so the function only needs to handle the two remaining normalization steps.

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

Returns a `String` (not `Uri`) — used directly as the DB column value and composite cache key `(catalog_id, normalizeUrl(url))`.

---

## `CachingFeedRepository`

**File:** `lib/data/caching_feed_repository.dart`

```dart
class CachingFeedRepository implements FeedRepository {
  CachingFeedRepository(AppDatabase db, OpdsClient client);
}
```

Constructor injection matches the existing repository pattern (`SqfliteCatalogRepository`, etc.). No additional classes or DAOs.

### `getFeed` algorithm

```
getFeed(catalogId, url, {forceRefresh = false}):
  key = normalizeUrl(url)

  if not forceRefresh:
    row = SELECT * FROM feed_cache WHERE catalog_id=? AND url=?
    if row exists:
      return CachedFeed(
        feed: ParsedFeed.fromJson(jsonDecode(row['feed_json'])),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at']),
        fromCache: true,
      )

  feed = await _fetchAllPages(url)
  now  = DateTime.now()
  INSERT OR REPLACE INTO feed_cache VALUES (catalogId, key, jsonEncode(feed.toJson()), now.millisecondsSinceEpoch)

  return CachedFeed(feed: feed, fetchedAt: now, fromCache: false)
```

The `INSERT OR REPLACE` overwrites on the composite primary key `(catalog_id, url)`, implementing the cache-overwrite-on-refresh behaviour required by §7.1.

### `_fetchAllPages` algorithm

Private method. Follows `nextPageUrl` links, merges entries from all pages into one flat `ParsedFeed`.

```
_fetchAllPages(Uri startUrl) → ParsedFeed:
  allEntries = []
  title = ''
  pageUrl = startUrl
  pageCount = 0

  loop:
    feed = await client.fetchFeed(pageUrl)
    if pageCount == 0: title = feed.title   # first page title
    allEntries.addAll(feed.entries)
    pageCount++
    if feed.nextPageUrl == null: break
    if pageCount >= 50: break               # page cap (§7.3)
    if allEntries.length >= 5000: break     # entry cap (§7.3)
    pageUrl = feed.nextPageUrl

  return ParsedFeed(title: title, entries: allEntries, nextPageUrl: null)
```

The merged `ParsedFeed` always has `nextPageUrl: null` — the full sequence is stored as one flat document in `feed_cache.feed_json`.

Title comes from the **first** page (the root feed name is most useful to the user).

Safety caps match §7.3: 50 pages or 5000 entries, whichever comes first. On hitting a cap the already-collected entries are cached and returned without error.

---

## Testing

### `url_normalizer_test.dart` — pure unit tests

| Scenario | Input | Expected output |
|---|---|---|
| Fragment stripped | `http://a.com/p#frag` | `http://a.com/p` |
| Default HTTP port removed | `http://a.com:80/p` | `http://a.com/p` |
| Default HTTPS port removed | `https://a.com:443/p` | `https://a.com/p` |
| Non-default port kept | `http://a.com:8080/p` | `http://a.com:8080/p` |
| Scheme/host roundtrip | `http://A.COM/p` | `http://a.com/p` (via `Uri.parse`) |
| Query preserved | `http://a.com/p?q=1` | `http://a.com/p?q=1` |

### `caching_feed_repository_test.dart` — sqflite_common_ffi + fake `OpdsClient`

The fake `OpdsClient` is a simple in-test class with a queue of `ParsedFeed` responses (not a separate file).

| Scenario | Verifies |
|---|---|
| Cache miss | Client called once; row written to DB; `fromCache: false` |
| Cache hit | Client not called; `fromCache: true`; `fetchedAt` matches stored value |
| `forceRefresh: true` with cached row | Client called; row overwritten; `fromCache: false` |
| Multi-page (3 pages) | Merged feed has all entries; `nextPageUrl: null`; single DB row |
| Page cap (50 pages) | Loop stops at 50; partial result stored |
| Entry cap (5000 entries) | Loop stops when entry count reaches 5000 |
| `fetched_at` round-trip | `DateTime` stored as epoch millis; retrieved correctly |

---

## Constraints carried over from spec

- `PRAGMA foreign_keys = ON` is set by `AppDatabase.onConfigure` — no action needed here.
- `feed_cache` rows cascade-delete when the parent `catalogs` row is deleted — already in the schema.
- All tests run with `flutter test` on host (no device, no emulator).
- `flutter analyze` must be clean and `flutter test` must pass before step is complete.

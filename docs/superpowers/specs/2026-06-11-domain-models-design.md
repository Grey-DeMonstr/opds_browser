# Domain Models, OpdsClient Interface & Fixtures — Design

**Step:** 2 of 14 (spec §14)
**Date:** 2026-06-11
**Status:** Approved

---

## Scope

This step implements the pure-Dart domain layer that all subsequent steps depend on:

- Domain model classes with JSON serialization
- Entity classes (no serialization needed — mapped directly to/from DB columns)
- Repository interfaces
- `OpdsClient` interface and exception hierarchy
- 12 XML test fixture files
- JSON roundtrip unit tests for all feed models

No Flutter bindings. No network calls. No DB calls. Everything in `lib/domain/` and `test/domain/` is pure Dart.

---

## File Layout

```
lib/domain/
  models.dart        # ParsedFeed, FeedEntry (sealed), NavigationEntry, BookEntry,
                     # AcquisitionLink, CachedFeed
  entities.dart      # Catalog, Favorite, AppSettings, DownloadTarget (sealed)
  repositories.dart  # CatalogRepository, FeedRepository, FavoritesRepository,
                     # SettingsRepository
  opds_client.dart   # OpdsClient interface + OpdsException hierarchy

test/domain/
  models_test.dart   # JSON roundtrip tests for all feed models

test/fixtures/
  minimal_navigation_feed.xml
  mixed_feed.xml
  book_multi_format_fb2.xml
  book_no_fb2.xml
  series_calibre.xml
  series_link.xml
  paginated_page1.xml
  paginated_page2.xml
  windows1251.xml        # binary, windows-1251 encoded
  malformed.xml
  empty_feed.xml
  relative_hrefs.xml
```

---

## models.dart

### `ParsedFeed`

```dart
class ParsedFeed {
  final String title;
  final List<FeedEntry> entries;
  final Uri? nextPageUrl;

  const ParsedFeed({required this.title, required this.entries, this.nextPageUrl});

  Map<String, dynamic> toJson() => {
    'title': title,
    'entries': entries.map((e) => e.toJson()).toList(),
    if (nextPageUrl != null) 'nextPageUrl': nextPageUrl.toString(),
  };

  factory ParsedFeed.fromJson(Map<String, dynamic> json) => ParsedFeed(
    title: json['title'] as String,
    entries: (json['entries'] as List<dynamic>)
        .map((e) => FeedEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextPageUrl: json['nextPageUrl'] != null
        ? Uri.parse(json['nextPageUrl'] as String)
        : null,
  );
}
```

### `FeedEntry` (sealed) + subclasses

`FeedEntry` is a sealed class. Each subclass includes a `'type'` discriminator key in its `toJson()` output so `FeedEntry.fromJson` can reconstruct the correct subtype:

```dart
sealed class FeedEntry {
  Map<String, dynamic> toJson();

  static FeedEntry fromJson(Map<String, dynamic> json) =>
    switch (json['type'] as String) {
      'nav'  => NavigationEntry.fromJson(json),
      'book' => BookEntry.fromJson(json),
      _      => throw FormatException('unknown FeedEntry type: ${json['type']}'),
    };
}

class NavigationEntry extends FeedEntry {
  final String title;
  final String? subtitle;
  final Uri url;
  // toJson() emits 'type': 'nav'
}

class BookEntry extends FeedEntry {
  final String title;
  final List<String> authors;
  final String? series;
  final double? seriesIndex;
  final String? summary;
  final Uri? coverUrl;
  final List<AcquisitionLink> acquisitionLinks;
  // toJson() emits 'type': 'book'
}

class AcquisitionLink {
  final Uri url;
  final String mimeType;
  final String formatLabel;
  // toJson() / fromJson() — no discriminator needed, always AcquisitionLink
}
```

### `CachedFeed`

A runtime wrapper returned by `FeedRepository`. Never persisted directly — the DB stores only the inner `ParsedFeed` as JSON. No `toJson`/`fromJson`.

```dart
class CachedFeed {
  final ParsedFeed feed;
  final DateTime fetchedAt;
  final bool fromCache;
}
```

---

## entities.dart

### `DownloadTarget` (sealed class)

Two variants: one is a unit type, one carries a URI string. Stored in `shared_preferences` via two keys (`download_target_kind`, `download_target_uri`) — not as JSON, so no `toJson` needed.

```dart
sealed class DownloadTarget { const DownloadTarget(); }
class SystemDownloads extends DownloadTarget { const SystemDownloads(); }
class CustomSafFolder extends DownloadTarget {
  final String uriString;
  const CustomSafFolder(this.uriString);
}
```

### Other entities

```dart
class Catalog {
  final int id;
  final String title;
  final Uri rootUrl;
  final String protocol;   // 'opds1'
}

class Favorite {
  final int id;
  final int catalogId;
  final Uri url;
  final String title;
  final int sortOrder;
}

class AppSettings {
  final DownloadTarget target;
  final bool createAuthorFolder;    // default false
  final bool createSeriesFolder;    // default false
}
```

No `toJson`/`fromJson` on any entity — they are assembled from DB columns or `shared_preferences` keys by the data layer.

---

## repositories.dart

Interfaces exactly as specified in §5 of the spec. Reproduced here for completeness:

```dart
abstract interface class CatalogRepository {
  Future<List<Catalog>> getAll();
  Future<Catalog> add(String title, Uri rootUrl);
  Future<void> update(Catalog catalog);
  Future<void> delete(int catalogId);
}

abstract interface class FeedRepository {
  Future<CachedFeed> getFeed(int catalogId, Uri url, {bool forceRefresh = false});
}

abstract interface class FavoritesRepository {
  Future<List<Favorite>> getAll();
  Future<void> add(int catalogId, Uri url, String title);
  Future<void> remove(int favoriteId);
  Future<bool> isFavorite(int catalogId, Uri url);
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
```

---

## opds_client.dart

### `OpdsClient` interface

```dart
abstract interface class OpdsClient {
  Future<ParsedFeed> fetchFeed(Uri url);
  Future<bool> probe(Uri url);
}
```

### Exception hierarchy

```dart
sealed class OpdsException implements Exception {
  final String message;
  const OpdsException(this.message);
}

class NetworkException extends OpdsException {
  const NetworkException(super.message);
}

class HttpStatusException extends OpdsException {
  final int statusCode;
  const HttpStatusException(this.statusCode, super.message);
}

class ParseException extends OpdsException {
  const ParseException(super.message);
}

class UnsupportedProtocolException extends OpdsException {
  const UnsupportedProtocolException(super.message);
}
```

---

## JSON Serialization Rules

- All serialization is manual (no `json_annotation`, no `build_runner`).
- `Uri` fields are serialized as `String` (`.toString()` / `Uri.parse()`).
- `double?` fields (`seriesIndex`) use `as double?` cast.
- Nullable fields are omitted from the map when null (using `if (x != null) 'key': x` spread-if pattern).
- `List` fields are never omitted when empty — always emitted as `[]`.
- `FeedEntry.fromJson` throws `FormatException` on unknown `'type'`; this surfaces as a `ParseException` at the Opds1Client boundary (step 3).

---

## Test Fixtures

12 files under `test/fixtures/`. Each is a realistic but minimal Atom/OPDS 1.x XML document. Content notes:

| File | Key characteristics |
|------|-------------------|
| `minimal_navigation_feed.xml` | 3 navigation entries, absolute hrefs, no books |
| `mixed_feed.xml` | 2 nav entries + 2 book entries interleaved |
| `book_multi_format_fb2.xml` | 1 book with FB2, FB2.ZIP, EPUB, PDF acquisition links |
| `book_no_fb2.xml` | 1 book with only EPUB and PDF |
| `series_calibre.xml` | 1 book with `<meta name="calibre:series">` + `calibre:series_index` |
| `series_link.xml` | 1 book with `<dcterms:isPartOf>` series pattern |
| `paginated_page1.xml` | 5 entries + `<link rel="next">` pointing to page 2 |
| `paginated_page2.xml` | 5 entries, no `rel="next"` |
| `windows1251.xml` | Minimal feed, `<?xml encoding="windows-1251"?>`, stored as binary bytes |
| `malformed.xml` | Truncated XML — causes parse error |
| `empty_feed.xml` | Valid Atom feed, zero `<entry>` elements |
| `relative_hrefs.xml` | `xml:base` on `<feed>`, all `href`s relative; resolved hrefs must equal absolute equivalents |

The windows-1251 fixture is stored as raw bytes (not UTF-8 source). The test that uses it reads the bytes directly via `File.readAsBytes()`.

---

## Unit Tests (test/domain/models_test.dart)

One `group` per class. Each group covers:

1. `toJson` produces the expected `Map<String, dynamic>` (spot-check key values)
2. `fromJson(x.toJson()) == x` roundtrip (all fields, including nulls and empty lists)
3. Null/optional field variants: missing optional field in map → null in object; null field in object → key absent in map
4. `FeedEntry.fromJson` with unknown `'type'` throws `FormatException`

No fixture XML is read in `models_test.dart` — all input is inline Dart maps. Fixtures are used in step 3 only.

---

## What This Step Does NOT Include

- `Opds1Client` implementation (step 3)
- DB schema or DAO implementations (step 4)
- `FeedRepository` caching logic (step 5)
- Any Flutter widget or provider code
- `normalizeUrl`, `extractSeries`, `preferredLink`, `buildFileName` pure functions — those are implemented in the steps where they're first needed (steps 3, 9)

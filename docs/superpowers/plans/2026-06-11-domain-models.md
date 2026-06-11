# Domain Models, OpdsClient Interface & Fixtures — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the complete pure-Dart domain layer — model classes with JSON serialization, entity classes, repository interfaces, `OpdsClient` interface, exception hierarchy, and 12 XML test fixtures — all verified by unit tests.

**Architecture:** Four files in `lib/domain/` hold all domain types. Models (`ParsedFeed`, `BookEntry`, etc.) are the only classes that serialize to/from JSON; this JSON is later stored verbatim in the SQLite feed cache. Entities map directly to DB columns or prefs keys. Repository interfaces and `OpdsClient` are pure contracts; no implementations live here. All classes are plain Dart — no Flutter imports.

**Tech Stack:** Dart 3 (sealed classes, switch expressions), `flutter_test` for unit tests, PowerShell for the binary windows-1251 fixture.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/domain/opds_client.dart` | Create | `OpdsClient` interface + `OpdsException` sealed hierarchy |
| `lib/domain/entities.dart` | Create | `Catalog`, `Favorite`, `AppSettings`, `DownloadTarget` (sealed) |
| `lib/domain/repositories.dart` | Create | Four repository interfaces |
| `lib/domain/models.dart` | Create (grows across tasks 3–6) | `AcquisitionLink`, `NavigationEntry`, `BookEntry`, `FeedEntry`, `ParsedFeed`, `CachedFeed` |
| `test/domain/exceptions_test.dart` | Create | Instantiation tests for every exception subclass |
| `test/domain/entities_test.dart` | Create | Field-access tests for every entity class |
| `test/domain/models_test.dart` | Create (grows across tasks 3–6) | JSON roundtrip tests for all feed model classes |
| `test/fixtures/*.xml` (12 files) | Create | OPDS 1.x XML samples for step-3 parser TDD |

> **Note on repository interfaces:** `CatalogRepository`, `FeedRepository`, `FavoritesRepository`, and `SettingsRepository` are abstract interfaces — they cannot be instantiated. Their contracts are tested via concrete implementations in steps 4–5. No unit tests are written for them in this step.

---

## Task 1: `opds_client.dart` — OpdsClient interface + exception hierarchy

**Files:**
- Create: `lib/domain/opds_client.dart`
- Create: `test/domain/exceptions_test.dart`

- [ ] **Step 1.1 — Write failing exception tests**

Create `test/domain/exceptions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  group('OpdsException hierarchy', () {
    test('NetworkException stores message and is an OpdsException', () {
      const e = NetworkException('no connection');
      expect(e.message, 'no connection');
      expect(e, isA<OpdsException>());
      expect(e, isA<Exception>());
    });

    test('HttpStatusException stores statusCode and message', () {
      const e = HttpStatusException(404, 'not found');
      expect(e.statusCode, 404);
      expect(e.message, 'not found');
      expect(e, isA<OpdsException>());
    });

    test('ParseException stores message', () {
      const e = ParseException('bad xml');
      expect(e.message, 'bad xml');
      expect(e, isA<OpdsException>());
    });

    test('UnsupportedProtocolException stores message', () {
      const e = UnsupportedProtocolException('not opds');
      expect(e.message, 'not opds');
      expect(e, isA<OpdsException>());
    });
  });
}
```

- [ ] **Step 1.2 — Run tests; confirm they fail**

```powershell
dart run tool/check.dart
```

Expected: compile error — `package:opds_browser/domain/opds_client.dart` not found.

- [ ] **Step 1.3 — Create `lib/domain/opds_client.dart`**

```dart
import 'package:opds_browser/domain/models.dart';

abstract interface class OpdsClient {
  Future<ParsedFeed> fetchFeed(Uri url);
  Future<bool> probe(Uri url);
}

sealed class OpdsException implements Exception {
  final String message;
  const OpdsException(this.message);

  @override
  String toString() => '$runtimeType: $message';
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

> Note: `opds_client.dart` imports `models.dart` for the `ParsedFeed` return type. `models.dart` doesn't exist yet — the file will fail to compile until Task 3 creates it. That's fine; `dart run tool/check.dart` is run after Task 3's commit, not here.

- [ ] **Step 1.4 — Commit**

```powershell
git add lib/domain/opds_client.dart test/domain/exceptions_test.dart
git commit -m "feat(domain): add OpdsClient interface and exception hierarchy"
```

---

## Task 2: `entities.dart` + `repositories.dart`

**Files:**
- Create: `lib/domain/entities.dart`
- Create: `lib/domain/repositories.dart`
- Create: `test/domain/entities_test.dart`

- [ ] **Step 2.1 — Write failing entity tests**

Create `test/domain/entities_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  group('Catalog', () {
    test('stores all fields', () {
      final c = Catalog(
        id: 1,
        title: 'Test Catalog',
        rootUrl: Uri.parse('https://example.com/opds'),
        protocol: 'opds1',
      );
      expect(c.id, 1);
      expect(c.title, 'Test Catalog');
      expect(c.rootUrl, Uri.parse('https://example.com/opds'));
      expect(c.protocol, 'opds1');
    });
  });

  group('Favorite', () {
    test('stores all fields', () {
      final f = Favorite(
        id: 2,
        catalogId: 1,
        url: Uri.parse('https://example.com/opds/sci-fi'),
        title: 'Science Fiction',
        sortOrder: 0,
      );
      expect(f.id, 2);
      expect(f.catalogId, 1);
      expect(f.url, Uri.parse('https://example.com/opds/sci-fi'));
      expect(f.title, 'Science Fiction');
      expect(f.sortOrder, 0);
    });
  });

  group('DownloadTarget', () {
    test('SystemDownloads is a DownloadTarget', () {
      const d = SystemDownloads();
      expect(d, isA<DownloadTarget>());
    });

    test('CustomSafFolder stores uriString', () {
      const d = CustomSafFolder('content://com.example/tree/doc');
      expect(d, isA<DownloadTarget>());
      expect(d.uriString, 'content://com.example/tree/doc');
    });
  });

  group('AppSettings', () {
    test('defaults createAuthorFolder and createSeriesFolder to false', () {
      const s = AppSettings(target: SystemDownloads());
      expect(s.createAuthorFolder, isFalse);
      expect(s.createSeriesFolder, isFalse);
      expect(s.target, isA<SystemDownloads>());
    });

    test('stores custom target and folder flags', () {
      const s = AppSettings(
        target: CustomSafFolder('content://uri'),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(s.target, isA<CustomSafFolder>());
      expect((s.target as CustomSafFolder).uriString, 'content://uri');
      expect(s.createAuthorFolder, isTrue);
      expect(s.createSeriesFolder, isTrue);
    });
  });
}
```

- [ ] **Step 2.2 — Run tests; confirm they fail**

```powershell
dart run tool/check.dart
```

Expected: compile error — `package:opds_browser/domain/entities.dart` not found.

- [ ] **Step 2.3 — Create `lib/domain/entities.dart`**

```dart
sealed class DownloadTarget {
  const DownloadTarget();
}

class SystemDownloads extends DownloadTarget {
  const SystemDownloads();
}

class CustomSafFolder extends DownloadTarget {
  final String uriString;
  const CustomSafFolder(this.uriString);
}

class Catalog {
  final int id;
  final String title;
  final Uri rootUrl;
  final String protocol;

  const Catalog({
    required this.id,
    required this.title,
    required this.rootUrl,
    required this.protocol,
  });
}

class Favorite {
  final int id;
  final int catalogId;
  final Uri url;
  final String title;
  final int sortOrder;

  const Favorite({
    required this.id,
    required this.catalogId,
    required this.url,
    required this.title,
    required this.sortOrder,
  });
}

class AppSettings {
  final DownloadTarget target;
  final bool createAuthorFolder;
  final bool createSeriesFolder;

  const AppSettings({
    required this.target,
    this.createAuthorFolder = false,
    this.createSeriesFolder = false,
  });
}
```

- [ ] **Step 2.4 — Create `lib/domain/repositories.dart`**

```dart
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

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

> `repositories.dart` imports `models.dart` for `CachedFeed`. That file doesn't exist until Task 3; `dart run tool/check.dart` is run after Task 3.

- [ ] **Step 2.5 — Commit**

```powershell
git add lib/domain/entities.dart lib/domain/repositories.dart test/domain/entities_test.dart
git commit -m "feat(domain): add entities, DownloadTarget, and repository interfaces"
```

---

## Task 3: `AcquisitionLink` — first model class (TDD)

**Files:**
- Create: `lib/domain/models.dart`
- Create: `test/domain/models_test.dart`

- [ ] **Step 3.1 — Write failing AcquisitionLink roundtrip test**

Create `test/domain/models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/models.dart';

void main() {
  group('AcquisitionLink', () {
    test('toJson / fromJson roundtrip', () {
      final link = AcquisitionLink(
        url: Uri.parse('https://example.com/book.fb2'),
        mimeType: 'application/fb2',
        formatLabel: 'FB2',
      );
      final json = link.toJson();
      expect(json['url'], 'https://example.com/book.fb2');
      expect(json['mimeType'], 'application/fb2');
      expect(json['formatLabel'], 'FB2');
      final restored = AcquisitionLink.fromJson(json);
      expect(restored.url, link.url);
      expect(restored.mimeType, link.mimeType);
      expect(restored.formatLabel, link.formatLabel);
    });
  });
}
```

- [ ] **Step 3.2 — Run tests; confirm they fail**

```powershell
dart run tool/check.dart
```

Expected: compile error — `package:opds_browser/domain/models.dart` not found.

- [ ] **Step 3.3 — Create `lib/domain/models.dart` with `AcquisitionLink`**

```dart
class AcquisitionLink {
  final Uri url;
  final String mimeType;
  final String formatLabel;

  const AcquisitionLink({
    required this.url,
    required this.mimeType,
    required this.formatLabel,
  });

  Map<String, dynamic> toJson() => {
        'url': url.toString(),
        'mimeType': mimeType,
        'formatLabel': formatLabel,
      };

  factory AcquisitionLink.fromJson(Map<String, dynamic> json) => AcquisitionLink(
        url: Uri.parse(json['url'] as String),
        mimeType: json['mimeType'] as String,
        formatLabel: json['formatLabel'] as String,
      );
}
```

- [ ] **Step 3.4 — Run all checks; confirm they pass**

```powershell
dart run tool/check.dart
```

Expected output ends with: `All checks passed.`

> At this point `opds_client.dart` and `repositories.dart` also compile for the first time (their import of `models.dart` is now satisfied — `ParsedFeed` and `CachedFeed` don't exist yet, but they will in Tasks 5–6; for now the files compile because the import is resolved). Actually, `opds_client.dart` references `ParsedFeed` which isn't defined yet — this will be a compile error. That's acceptable; it will be resolved in Task 6. To avoid blocking `dart run tool/check.dart`, add a forward-reference stub in `models.dart` now by adding an empty placeholder class, then replace it in Task 6.

Add after `AcquisitionLink` in `lib/domain/models.dart`:

```dart
// Stubs to allow opds_client.dart and repositories.dart to compile.
// Replaced with full implementations in Tasks 4–6.
class ParsedFeed {
  const ParsedFeed();
}

class CachedFeed {
  const CachedFeed();
}
```

Then re-run:

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 3.5 — Commit**

```powershell
git add lib/domain/models.dart test/domain/models_test.dart
git commit -m "feat(domain): add AcquisitionLink with JSON serialization"
```

---

## Task 4: `FeedEntry` (sealed stub) + `NavigationEntry` (TDD)

**Files:**
- Modify: `lib/domain/models.dart` — add `FeedEntry` sealed class and `NavigationEntry`
- Modify: `test/domain/models_test.dart` — add `NavigationEntry` group

- [ ] **Step 4.1 — Add failing NavigationEntry tests**

Append to the `main()` body in `test/domain/models_test.dart` (after the closing `});` of the `AcquisitionLink` group):

```dart
  group('NavigationEntry', () {
    test('toJson / fromJson roundtrip — with subtitle', () {
      final entry = NavigationEntry(
        title: 'Science Fiction',
        subtitle: 'Explore the cosmos',
        url: Uri.parse('https://example.com/sci-fi'),
      );
      final json = entry.toJson();
      expect(json['type'], 'nav');
      expect(json['title'], 'Science Fiction');
      expect(json['subtitle'], 'Explore the cosmos');
      expect(json['url'], 'https://example.com/sci-fi');
      final restored = NavigationEntry.fromJson(json);
      expect(restored.title, entry.title);
      expect(restored.subtitle, entry.subtitle);
      expect(restored.url, entry.url);
    });

    test('toJson omits subtitle when null; fromJson restores null', () {
      final entry = NavigationEntry(
        title: 'Fantasy',
        subtitle: null,
        url: Uri.parse('https://example.com/fantasy'),
      );
      final json = entry.toJson();
      expect(json.containsKey('subtitle'), isFalse);
      final restored = NavigationEntry.fromJson(json);
      expect(restored.subtitle, isNull);
    });
  });
```

- [ ] **Step 4.2 — Run tests; confirm they fail**

```powershell
dart run tool/check.dart
```

Expected: compile error — `NavigationEntry` not defined.

- [ ] **Step 4.3 — Replace the stub `ParsedFeed` and `CachedFeed` in `models.dart` with `FeedEntry` + `NavigationEntry`**

Replace the entire `lib/domain/models.dart` with:

```dart
class AcquisitionLink {
  final Uri url;
  final String mimeType;
  final String formatLabel;

  const AcquisitionLink({
    required this.url,
    required this.mimeType,
    required this.formatLabel,
  });

  Map<String, dynamic> toJson() => {
        'url': url.toString(),
        'mimeType': mimeType,
        'formatLabel': formatLabel,
      };

  factory AcquisitionLink.fromJson(Map<String, dynamic> json) => AcquisitionLink(
        url: Uri.parse(json['url'] as String),
        mimeType: json['mimeType'] as String,
        formatLabel: json['formatLabel'] as String,
      );
}

/// Sealed base for feed entries. [fromJson] is added in Task 6
/// once all subclasses exist.
sealed class FeedEntry {
  const FeedEntry();
  Map<String, dynamic> toJson();
}

class NavigationEntry extends FeedEntry {
  final String title;
  final String? subtitle;
  final Uri url;

  const NavigationEntry({
    required this.title,
    this.subtitle,
    required this.url,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'nav',
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'url': url.toString(),
      };

  factory NavigationEntry.fromJson(Map<String, dynamic> json) => NavigationEntry(
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        url: Uri.parse(json['url'] as String),
      );
}

// Stubs — replaced in Tasks 5 and 6.
class BookEntry extends FeedEntry {
  const BookEntry();
  @override
  Map<String, dynamic> toJson() => const {};
}

class ParsedFeed {
  const ParsedFeed();
}

class CachedFeed {
  const CachedFeed();
}
```

- [ ] **Step 4.4 — Run all checks; confirm they pass**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 4.5 — Commit**

```powershell
git add lib/domain/models.dart test/domain/models_test.dart
git commit -m "feat(domain): add FeedEntry sealed class and NavigationEntry"
```

---

## Task 5: `BookEntry` (TDD)

**Files:**
- Modify: `lib/domain/models.dart` — replace `BookEntry` stub with full implementation
- Modify: `test/domain/models_test.dart` — add `BookEntry` group

- [ ] **Step 5.1 — Add failing BookEntry tests**

Append to the `main()` body in `test/domain/models_test.dart` (after the `NavigationEntry` group):

```dart
  group('BookEntry', () {
    test('toJson / fromJson roundtrip — all fields present', () {
      final entry = BookEntry(
        title: 'The Dart Language',
        authors: ['Alice Author', 'Bob Coauthor'],
        series: 'Dart Series',
        seriesIndex: 1.5,
        summary: 'An intro to Dart.',
        coverUrl: Uri.parse('https://example.com/cover.jpg'),
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/book.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      );
      final json = entry.toJson();
      expect(json['type'], 'book');
      expect(json['title'], 'The Dart Language');
      expect(json['authors'], ['Alice Author', 'Bob Coauthor']);
      expect(json['series'], 'Dart Series');
      expect(json['seriesIndex'], 1.5);
      expect(json['summary'], 'An intro to Dart.');
      expect(json['coverUrl'], 'https://example.com/cover.jpg');
      expect((json['acquisitionLinks'] as List<dynamic>).length, 1);

      final restored = BookEntry.fromJson(json);
      expect(restored.title, entry.title);
      expect(restored.authors, entry.authors);
      expect(restored.series, entry.series);
      expect(restored.seriesIndex, entry.seriesIndex);
      expect(restored.summary, entry.summary);
      expect(restored.coverUrl, entry.coverUrl);
      expect(restored.acquisitionLinks.length, 1);
      expect(restored.acquisitionLinks.first.formatLabel, 'FB2');
    });

    test('toJson omits nullable fields when null; fromJson restores nulls', () {
      final entry = BookEntry(
        title: 'Minimal Book',
        authors: const [],
        series: null,
        seriesIndex: null,
        summary: null,
        coverUrl: null,
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/min.epub'),
            mimeType: 'application/epub+zip',
            formatLabel: 'EPUB',
          ),
        ],
      );
      final json = entry.toJson();
      expect(json.containsKey('series'), isFalse);
      expect(json.containsKey('seriesIndex'), isFalse);
      expect(json.containsKey('summary'), isFalse);
      expect(json.containsKey('coverUrl'), isFalse);
      expect(json['authors'], isEmpty);

      final restored = BookEntry.fromJson(json);
      expect(restored.series, isNull);
      expect(restored.seriesIndex, isNull);
      expect(restored.summary, isNull);
      expect(restored.coverUrl, isNull);
      expect(restored.authors, isEmpty);
    });

    test('integer seriesIndex round-trips as double', () {
      final entry = BookEntry(
        title: 'Book 1',
        authors: const ['Author'],
        series: 'Series',
        seriesIndex: 1.0,
        summary: null,
        coverUrl: null,
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/b.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      );
      final restored = BookEntry.fromJson(entry.toJson());
      expect(restored.seriesIndex, 1.0);
    });
  });
```

- [ ] **Step 5.2 — Run tests; confirm they fail**

```powershell
dart run tool/check.dart
```

Expected: compile error or test failure — `BookEntry` constructor doesn't match.

- [ ] **Step 5.3 — Replace the `BookEntry` stub in `lib/domain/models.dart`**

Replace the `BookEntry` class (the stub with `const BookEntry();`) with:

```dart
class BookEntry extends FeedEntry {
  final String title;
  final List<String> authors;
  final String? series;
  final double? seriesIndex;
  final String? summary;
  final Uri? coverUrl;
  final List<AcquisitionLink> acquisitionLinks;

  const BookEntry({
    required this.title,
    required this.authors,
    this.series,
    this.seriesIndex,
    this.summary,
    this.coverUrl,
    required this.acquisitionLinks,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'book',
        'title': title,
        'authors': authors,
        if (series != null) 'series': series,
        if (seriesIndex != null) 'seriesIndex': seriesIndex,
        if (summary != null) 'summary': summary,
        if (coverUrl != null) 'coverUrl': coverUrl.toString(),
        'acquisitionLinks': acquisitionLinks.map((l) => l.toJson()).toList(),
      };

  factory BookEntry.fromJson(Map<String, dynamic> json) => BookEntry(
        title: json['title'] as String,
        authors: (json['authors'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        series: json['series'] as String?,
        seriesIndex: (json['seriesIndex'] as num?)?.toDouble(),
        summary: json['summary'] as String?,
        coverUrl: json['coverUrl'] != null
            ? Uri.parse(json['coverUrl'] as String)
            : null,
        acquisitionLinks: (json['acquisitionLinks'] as List<dynamic>)
            .map((l) => AcquisitionLink.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}
```

- [ ] **Step 5.4 — Run all checks; confirm they pass**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 5.5 — Commit**

```powershell
git add lib/domain/models.dart test/domain/models_test.dart
git commit -m "feat(domain): add BookEntry with full JSON serialization"
```

---

## Task 6: Complete `FeedEntry.fromJson` + `ParsedFeed` + `CachedFeed` (TDD)

**Files:**
- Modify: `lib/domain/models.dart` — complete `FeedEntry`, replace `ParsedFeed`/`CachedFeed` stubs
- Modify: `test/domain/models_test.dart` — add `FeedEntry` and `ParsedFeed` groups

- [ ] **Step 6.1 — Add failing FeedEntry and ParsedFeed tests**

Append to the `main()` body in `test/domain/models_test.dart` (after the `BookEntry` group):

```dart
  group('FeedEntry.fromJson', () {
    test('dispatches to NavigationEntry for type "nav"', () {
      final nav = NavigationEntry(
        title: 'Test Nav',
        subtitle: null,
        url: Uri.parse('https://example.com/nav'),
      );
      final restored = FeedEntry.fromJson(nav.toJson());
      expect(restored, isA<NavigationEntry>());
      expect((restored as NavigationEntry).title, 'Test Nav');
    });

    test('dispatches to BookEntry for type "book"', () {
      final book = BookEntry(
        title: 'Test Book',
        authors: const ['Author'],
        series: null,
        seriesIndex: null,
        summary: null,
        coverUrl: null,
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/book.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      );
      final restored = FeedEntry.fromJson(book.toJson());
      expect(restored, isA<BookEntry>());
    });

    test('throws FormatException for unknown type', () {
      expect(
        () => FeedEntry.fromJson({'type': 'unknown'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ParsedFeed', () {
    test('toJson / fromJson roundtrip — mixed entries and pagination', () {
      final feed = ParsedFeed(
        title: 'Test Feed',
        entries: [
          NavigationEntry(
            title: 'Nav Entry',
            subtitle: null,
            url: Uri.parse('https://example.com/nav'),
          ),
          BookEntry(
            title: 'Book Entry',
            authors: const ['Auth'],
            series: null,
            seriesIndex: null,
            summary: null,
            coverUrl: null,
            acquisitionLinks: [
              AcquisitionLink(
                url: Uri.parse('https://example.com/book.fb2'),
                mimeType: 'application/fb2',
                formatLabel: 'FB2',
              ),
            ],
          ),
        ],
        nextPageUrl: Uri.parse('https://example.com/feed?page=2'),
      );
      final restored = ParsedFeed.fromJson(feed.toJson());
      expect(restored.title, 'Test Feed');
      expect(restored.entries.length, 2);
      expect(restored.entries[0], isA<NavigationEntry>());
      expect(restored.entries[1], isA<BookEntry>());
      expect(restored.nextPageUrl, Uri.parse('https://example.com/feed?page=2'));
    });

    test('toJson omits nextPageUrl when null; fromJson restores null', () {
      final feed = ParsedFeed(
        title: 'Last Page',
        entries: const [],
        nextPageUrl: null,
      );
      final json = feed.toJson();
      expect(json.containsKey('nextPageUrl'), isFalse);
      expect(json['entries'], isEmpty);
      final restored = ParsedFeed.fromJson(json);
      expect(restored.nextPageUrl, isNull);
      expect(restored.entries, isEmpty);
    });
  });
```

- [ ] **Step 6.2 — Run tests; confirm they fail**

```powershell
dart run tool/check.dart
```

Expected: compile error — `ParsedFeed` stub has no constructor matching the test calls; `FeedEntry.fromJson` doesn't exist.

- [ ] **Step 6.3 — Replace the entire `lib/domain/models.dart` with the final version**

```dart
class AcquisitionLink {
  final Uri url;
  final String mimeType;
  final String formatLabel;

  const AcquisitionLink({
    required this.url,
    required this.mimeType,
    required this.formatLabel,
  });

  Map<String, dynamic> toJson() => {
        'url': url.toString(),
        'mimeType': mimeType,
        'formatLabel': formatLabel,
      };

  factory AcquisitionLink.fromJson(Map<String, dynamic> json) => AcquisitionLink(
        url: Uri.parse(json['url'] as String),
        mimeType: json['mimeType'] as String,
        formatLabel: json['formatLabel'] as String,
      );
}

sealed class FeedEntry {
  const FeedEntry();
  Map<String, dynamic> toJson();

  static FeedEntry fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'nav' => NavigationEntry.fromJson(json),
      'book' => BookEntry.fromJson(json),
      _ => throw FormatException('unknown FeedEntry type: $type'),
    };
  }
}

class NavigationEntry extends FeedEntry {
  final String title;
  final String? subtitle;
  final Uri url;

  const NavigationEntry({
    required this.title,
    this.subtitle,
    required this.url,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'nav',
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'url': url.toString(),
      };

  factory NavigationEntry.fromJson(Map<String, dynamic> json) => NavigationEntry(
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        url: Uri.parse(json['url'] as String),
      );
}

class BookEntry extends FeedEntry {
  final String title;
  final List<String> authors;
  final String? series;
  final double? seriesIndex;
  final String? summary;
  final Uri? coverUrl;
  final List<AcquisitionLink> acquisitionLinks;

  const BookEntry({
    required this.title,
    required this.authors,
    this.series,
    this.seriesIndex,
    this.summary,
    this.coverUrl,
    required this.acquisitionLinks,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'book',
        'title': title,
        'authors': authors,
        if (series != null) 'series': series,
        if (seriesIndex != null) 'seriesIndex': seriesIndex,
        if (summary != null) 'summary': summary,
        if (coverUrl != null) 'coverUrl': coverUrl.toString(),
        'acquisitionLinks': acquisitionLinks.map((l) => l.toJson()).toList(),
      };

  factory BookEntry.fromJson(Map<String, dynamic> json) => BookEntry(
        title: json['title'] as String,
        authors: (json['authors'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        series: json['series'] as String?,
        seriesIndex: (json['seriesIndex'] as num?)?.toDouble(),
        summary: json['summary'] as String?,
        coverUrl: json['coverUrl'] != null
            ? Uri.parse(json['coverUrl'] as String)
            : null,
        acquisitionLinks: (json['acquisitionLinks'] as List<dynamic>)
            .map((l) => AcquisitionLink.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

class ParsedFeed {
  final String title;
  final List<FeedEntry> entries;
  final Uri? nextPageUrl;

  const ParsedFeed({
    required this.title,
    required this.entries,
    this.nextPageUrl,
  });

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

class CachedFeed {
  final ParsedFeed feed;
  final DateTime fetchedAt;
  final bool fromCache;

  const CachedFeed({
    required this.feed,
    required this.fetchedAt,
    required this.fromCache,
  });
}
```

- [ ] **Step 6.4 — Run all checks; confirm they pass**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 6.5 — Commit**

```powershell
git add lib/domain/models.dart test/domain/models_test.dart
git commit -m "feat(domain): complete FeedEntry.fromJson, ParsedFeed, CachedFeed"
```

---

## Task 7: Navigation and structural XML fixtures

**Files:**
- Create: `test/fixtures/minimal_navigation_feed.xml`
- Create: `test/fixtures/mixed_feed.xml`
- Create: `test/fixtures/empty_feed.xml`
- Create: `test/fixtures/malformed.xml`

- [ ] **Step 7.1 — Create `test/fixtures/minimal_navigation_feed.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:minimal-nav</id>
  <title>Test Navigation Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <link rel="self" type="application/atom+xml;profile=opds-catalog"
        href="https://example.com/opds"/>
  <entry>
    <id>urn:example:nav-1</id>
    <title>Science Fiction</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <content type="text">Sci-fi books</content>
    <link rel="subsection"
          type="application/atom+xml;profile=opds-catalog;kind=navigation"
          href="https://example.com/opds/sci-fi"/>
  </entry>
  <entry>
    <id>urn:example:nav-2</id>
    <title>Fantasy</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <link rel="subsection"
          type="application/atom+xml;profile=opds-catalog;kind=navigation"
          href="https://example.com/opds/fantasy"/>
  </entry>
  <entry>
    <id>urn:example:nav-3</id>
    <title>Mystery</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <link rel="subsection"
          type="application/atom+xml;profile=opds-catalog;kind=navigation"
          href="https://example.com/opds/mystery"/>
  </entry>
</feed>
```

- [ ] **Step 7.2 — Create `test/fixtures/mixed_feed.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:mixed</id>
  <title>Mixed Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:nav-new</id>
    <title>New Arrivals</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <link rel="subsection"
          type="application/atom+xml;profile=opds-catalog"
          href="https://example.com/opds/new"/>
  </entry>
  <entry>
    <id>urn:example:book-dart</id>
    <title>The Dart Programming Language</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>John Doe</name></author>
    <summary>A book about Dart.</summary>
    <link rel="http://opds-spec.org/image/thumbnail" type="image/jpeg"
          href="https://example.com/covers/dart-thumb.jpg"/>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="https://example.com/books/dart.epub"/>
  </entry>
  <entry>
    <id>urn:example:nav-top</id>
    <title>Top Rated</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <link rel="subsection"
          type="application/atom+xml;profile=opds-catalog"
          href="https://example.com/opds/top"/>
  </entry>
  <entry>
    <id>urn:example:book-flutter</id>
    <title>Flutter in Action</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Jane Smith</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/flutter.fb2"/>
  </entry>
</feed>
```

- [ ] **Step 7.3 — Create `test/fixtures/empty_feed.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>urn:example:empty</id>
  <title>Empty Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
</feed>
```

- [ ] **Step 7.4 — Create `test/fixtures/malformed.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Broken Feed
```

(File ends here — deliberately truncated to trigger a parse error.)

- [ ] **Step 7.5 — Run checks; confirm they still pass**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.` (XML files are not imported by any Dart code yet; this just verifies nothing broke.)

- [ ] **Step 7.6 — Commit**

```powershell
git add test/fixtures/minimal_navigation_feed.xml test/fixtures/mixed_feed.xml test/fixtures/empty_feed.xml test/fixtures/malformed.xml
git commit -m "test(fixtures): add navigation, mixed, empty, and malformed feed fixtures"
```

---

## Task 8: Book entry XML fixtures

**Files:**
- Create: `test/fixtures/book_multi_format_fb2.xml`
- Create: `test/fixtures/book_no_fb2.xml`
- Create: `test/fixtures/series_calibre.xml`
- Create: `test/fixtures/series_link.xml`

- [ ] **Step 8.1 — Create `test/fixtures/book_multi_format_fb2.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:multi-format</id>
  <title>Multi-Format Book Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:book-multiformat</id>
    <title>Sample Book</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Alice Author</name></author>
    <author><name>Bob Coauthor</name></author>
    <summary>A book available in multiple formats.</summary>
    <link rel="http://opds-spec.org/image/thumbnail" type="image/jpeg"
          href="https://example.com/covers/sample-thumb.jpg"/>
    <link rel="http://opds-spec.org/image" type="image/jpeg"
          href="https://example.com/covers/sample-full.jpg"/>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/sample.fb2"/>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2+zip"
          href="https://example.com/books/sample.fb2.zip"/>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="https://example.com/books/sample.epub"/>
    <link rel="http://opds-spec.org/acquisition" type="application/pdf"
          href="https://example.com/books/sample.pdf"/>
  </entry>
</feed>
```

- [ ] **Step 8.2 — Create `test/fixtures/book_no_fb2.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:no-fb2</id>
  <title>No-FB2 Book Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:book-nofb2</id>
    <title>EPUB Only Book</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Carol Writer</name></author>
    <summary>This book has no FB2 format.</summary>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="https://example.com/books/epub-only.epub"/>
    <link rel="http://opds-spec.org/acquisition" type="application/pdf"
          href="https://example.com/books/epub-only.pdf"/>
  </entry>
</feed>
```

- [ ] **Step 8.3 — Create `test/fixtures/series_calibre.xml`**

Uses the Calibre XML namespace elements (`calibre:series` / `calibre:series_index`), which is the primary real-world Calibre OPDS format. The `Opds1Client` parser (step 3) will need to read these.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:calibre="http://calibre.kovidgoyal.net/2009/#"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:series-calibre</id>
  <title>Calibre Series Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:book-calibre-series</id>
    <title>The Fellowship of the Ring</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>J.R.R. Tolkien</name></author>
    <calibre:series>The Lord of the Rings</calibre:series>
    <calibre:series_index>1.0</calibre:series_index>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/fotr.fb2"/>
  </entry>
</feed>
```

- [ ] **Step 8.4 — Create `test/fixtures/series_link.xml`**

Uses `dcterms:isPartOf` — the non-Calibre series pattern mentioned in the spec.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dcterms="http://purl.org/dc/terms/"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:series-link</id>
  <title>Series (dcterms) Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:book-series-link</id>
    <title>The Two Towers</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>J.R.R. Tolkien</name></author>
    <dcterms:isPartOf>The Lord of the Rings</dcterms:isPartOf>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/ttt.fb2"/>
  </entry>
</feed>
```

- [ ] **Step 8.5 — Run checks**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 8.6 — Commit**

```powershell
git add test/fixtures/book_multi_format_fb2.xml test/fixtures/book_no_fb2.xml test/fixtures/series_calibre.xml test/fixtures/series_link.xml
git commit -m "test(fixtures): add book entry fixtures (multi-format, no-FB2, series variants)"
```

---

## Task 9: Pagination and URL fixtures

**Files:**
- Create: `test/fixtures/paginated_page1.xml`
- Create: `test/fixtures/paginated_page2.xml`
- Create: `test/fixtures/relative_hrefs.xml`

- [ ] **Step 9.1 — Create `test/fixtures/paginated_page1.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:paginated</id>
  <title>Paginated Feed — Page 1</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <link rel="next" type="application/atom+xml;profile=opds-catalog"
        href="https://example.com/opds/books?page=2"/>
  <entry>
    <id>urn:example:book-p1-1</id>
    <title>Book Page 1 — Entry 1</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Author One</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/p1e1.fb2"/>
  </entry>
  <entry>
    <id>urn:example:book-p1-2</id>
    <title>Book Page 1 — Entry 2</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Author Two</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/p1e2.fb2"/>
  </entry>
  <entry>
    <id>urn:example:book-p1-3</id>
    <title>Book Page 1 — Entry 3</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Author Three</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="https://example.com/books/p1e3.epub"/>
  </entry>
</feed>
```

- [ ] **Step 9.2 — Create `test/fixtures/paginated_page2.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:example:paginated</id>
  <title>Paginated Feed — Page 2</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:book-p2-1</id>
    <title>Book Page 2 — Entry 1</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Author Four</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/fb2"
          href="https://example.com/books/p2e1.fb2"/>
  </entry>
  <entry>
    <id>urn:example:book-p2-2</id>
    <title>Book Page 2 — Entry 2</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Author Five</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/pdf"
          href="https://example.com/books/p2e2.pdf"/>
  </entry>
</feed>
```

- [ ] **Step 9.3 — Create `test/fixtures/relative_hrefs.xml`**

The `xml:base` on the `<feed>` element is `https://example.com/catalog/`. The parser must resolve relative hrefs against this base.

Expected resolved URLs after parsing:
- nav entry `sub/` → `https://example.com/catalog/sub/`
- book acquisition `../books/rel.epub` → `https://example.com/books/rel.epub`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog"
      xml:base="https://example.com/catalog/">
  <id>urn:example:relative</id>
  <title>Relative Hrefs Feed</title>
  <updated>2024-01-01T00:00:00Z</updated>
  <entry>
    <id>urn:example:nav-rel</id>
    <title>Sub-category</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <link rel="subsection"
          type="application/atom+xml;profile=opds-catalog"
          href="sub/"/>
  </entry>
  <entry>
    <id>urn:example:book-rel</id>
    <title>Relative Book</title>
    <updated>2024-01-01T00:00:00Z</updated>
    <author><name>Dave Dev</name></author>
    <link rel="http://opds-spec.org/acquisition" type="application/epub+zip"
          href="../books/rel.epub"/>
  </entry>
</feed>
```

- [ ] **Step 9.4 — Run checks**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 9.5 — Commit**

```powershell
git add test/fixtures/paginated_page1.xml test/fixtures/paginated_page2.xml test/fixtures/relative_hrefs.xml
git commit -m "test(fixtures): add pagination and relative-href feed fixtures"
```

---

## Task 10: Binary windows-1251 fixture

**Files:**
- Create: `test/fixtures/windows1251.xml` (binary — windows-1251 encoded)

This fixture cannot be created as a UTF-8 source file. Use PowerShell to encode the content in windows-1251 and write the raw bytes.

- [ ] **Step 10.1 — Generate the binary fixture via PowerShell**

```powershell
$encoding = [System.Text.Encoding]::GetEncoding(1251)
$xml = "<?xml version=`"1.0`" encoding=`"windows-1251`"?>`r`n" +
       "<feed xmlns=`"http://www.w3.org/2005/Atom`">`r`n" +
       "  <id>urn:example:windows1251</id>`r`n" +
       "  <title>" + [char]0x041A + [char]0x0438 + [char]0x0440 + [char]0x0438 + [char]0x043B + [char]0x043B + [char]0x0438 + [char]0x0447 + [char]0x0435 + [char]0x0441 + [char]0x043A + [char]0x0438 + [char]0x0439 + " " + [char]0x043A + [char]0x0430 + [char]0x0442 + [char]0x0430 + [char]0x043B + [char]0x043E + [char]0x0433 + "</title>`r`n" +
       "  <updated>2024-01-01T00:00:00Z</updated>`r`n" +
       "  <entry>`r`n" +
       "    <id>urn:example:w1251-book</id>`r`n" +
       "    <title>" + [char]0x041C + [char]0x0430 + [char]0x0441 + [char]0x0442 + [char]0x0435 + [char]0x0440 + " " + [char]0x0438 + " " + [char]0x041C + [char]0x0430 + [char]0x0440 + [char]0x0433 + [char]0x0430 + [char]0x0440 + [char]0x0438 + [char]0x0442 + [char]0x0430 + "</title>`r`n" +
       "    <updated>2024-01-01T00:00:00Z</updated>`r`n" +
       "    <author><name>" + [char]0x041C + [char]0x0438 + [char]0x0445 + [char]0x0430 + [char]0x0438 + [char]0x043B + " " + [char]0x0411 + [char]0x0443 + [char]0x043B + [char]0x0433 + [char]0x0430 + [char]0x043A + [char]0x043E + [char]0x0432 + "</name></author>`r`n" +
       "    <link rel=`"http://opds-spec.org/acquisition`" type=`"application/fb2`"`r`n" +
       "          href=`"https://example.com/books/master.fb2`"/>`r`n" +
       "  </entry>`r`n" +
       "</feed>"
$bytes = $encoding.GetBytes($xml)
[System.IO.File]::WriteAllBytes("test\fixtures\windows1251.xml", $bytes)
Write-Host "Written $($bytes.Length) bytes"
```

The Unicode codepoints spell out:
- Feed title: "Кириллический каталог" (Cyrillic catalog)
- Book title: "Мастер и Маргарита" (The Master and Margarita)
- Author: "Михаил Булгаков" (Mikhail Bulgakov)

- [ ] **Step 10.2 — Verify the file was created as binary (not UTF-8)**

```powershell
$bytes = [System.IO.File]::ReadAllBytes("test\fixtures\windows1251.xml")
Write-Host "File size: $($bytes.Length) bytes"
# windows-1251 'К' = 0xCA; verify byte at position of the title
$bytes[0..4] | ForEach-Object { "0x{0:X2}" -f $_ }
```

Expected first 5 bytes: `0x3C 0x3F 0x78 0x6D 0x6C` (the ASCII bytes of `<?xml`).

- [ ] **Step 10.3 — Run checks**

```powershell
dart run tool/check.dart
```

Expected: `All checks passed.`

- [ ] **Step 10.4 — Commit**

```powershell
git add test/fixtures/windows1251.xml
git commit -m "test(fixtures): add windows-1251 binary encoded feed fixture"
```

---

## Task 11: Final verification

- [ ] **Step 11.1 — Run the full quality gate**

```powershell
dart run tool/check.dart
```

Expected output (abridged):

```
=== analyze: flutter analyze ===
Analyzing opds_browser...
No issues found!

=== test: flutter test ===
...............................................................................
All tests passed!

All checks passed.
```

- [ ] **Step 11.2 — Confirm all domain files exist**

```powershell
Get-ChildItem lib\domain\, test\domain\, test\fixtures\ -Recurse -File | Select-Object FullName
```

Expected files:
- `lib\domain\opds_client.dart`
- `lib\domain\entities.dart`
- `lib\domain\repositories.dart`
- `lib\domain\models.dart`
- `test\domain\exceptions_test.dart`
- `test\domain\entities_test.dart`
- `test\domain\models_test.dart`
- `test\fixtures\minimal_navigation_feed.xml`
- `test\fixtures\mixed_feed.xml`
- `test\fixtures\empty_feed.xml`
- `test\fixtures\malformed.xml`
- `test\fixtures\book_multi_format_fb2.xml`
- `test\fixtures\book_no_fb2.xml`
- `test\fixtures\series_calibre.xml`
- `test\fixtures\series_link.xml`
- `test\fixtures\paginated_page1.xml`
- `test\fixtures\paginated_page2.xml`
- `test\fixtures\relative_hrefs.xml`
- `test\fixtures\windows1251.xml`

---

## Self-Review Checklist

| Spec requirement | Task |
|---|---|
| `ParsedFeed` with `toJson`/`fromJson` | Task 6 |
| `FeedEntry` sealed class with type discriminator | Tasks 4 + 6 |
| `NavigationEntry` with all fields + serialization | Task 4 |
| `BookEntry` with all fields + serialization | Task 5 |
| `AcquisitionLink` with serialization | Task 3 |
| `CachedFeed` (no serialization) | Task 6 |
| `Catalog`, `Favorite`, `AppSettings` entities | Task 2 |
| `DownloadTarget` sealed class | Task 2 |
| `CatalogRepository`, `FeedRepository`, `FavoritesRepository`, `SettingsRepository` interfaces | Task 2 |
| `OpdsClient` interface | Task 1 |
| `OpdsException` hierarchy (all 4 subtypes) | Task 1 |
| Unit tests for every entity/model class | Tasks 1–6 |
| 12 XML fixture files | Tasks 7–10 |
| `dart run tool/check.dart` clean | Task 11 |
| Nullable fields absent from JSON when null | Tasks 3–6 (enforced by tests) |
| `seriesIndex` as `num` → `double` | Task 5 test step 5.1 |
| `FeedEntry.fromJson` throws `FormatException` for unknown type | Task 6 test step 6.1 |

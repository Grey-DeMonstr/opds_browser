# Single-Book Download + Bottom Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement single-book download end-to-end: pure format/filename functions, `BookDownloader` data class, `MediaStoreDownloadStorage`, `DownloadNotifier` Riverpod state, and the `BookDetailsSheet` UI with format picker and snackbar wiring.

**Architecture:** Pure functions `preferredLink`/`buildFileName`/`buildPathSegments` live in `lib/domain/download_utils.dart`; `BookDownloader` in `lib/data/` takes injected `http.Client` + `DownloadStorage`; `DownloadNotifier` is a non-autoDispose `Notifier.family` keyed by `AcquisitionLink.url`; `BookDetailsSheet` is a `ConsumerStatefulWidget` tracking `_activeDownloadUrl` to watch the correct notifier instance; `_BrowseContent` listens to `lastDownloadResultProvider` for the completion snackbar.

**Tech Stack:** Flutter, Riverpod 3.x (`Notifier.family`), `http ^1.6.0` + `MockClient`, `media_store_plus`, `open_filex`, `cached_network_image`, `flutter_test`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `pubspec.yaml` | Modify | Add `media_store_plus` |
| `lib/domain/download_utils.dart` | Create | `preferredLink`, `buildFileName`, `buildPathSegments` pure functions |
| `lib/data/media_store_download_storage.dart` | Create | `MediaStoreDownloadStorage` — MediaStore Downloads via `media_store_plus` |
| `lib/data/book_downloader.dart` | Create | `BookDownloader(http.Client, DownloadStorage)` — HTTP fetch + storage write |
| `lib/ui/providers.dart` | Modify | `DownloadState` sealed class, `DownloadNotifier`, `httpClientProvider`, `bookDownloaderProvider`, `downloadNotifierProvider`, `lastDownloadResultProvider`; update `downloadStorageProvider` |
| `lib/ui/book_details_sheet.dart` | Create | `BookDetailsSheet` modal bottom sheet + `_showFormatPicker` dialog |
| `lib/ui/browse_screen.dart` | Modify | `_BookEntryTile` gains `onTap`; `_BrowseContent` gains `ref.listen` for completion snackbar |
| `test/domain/download_utils_test.dart` | Create | Unit tests for all three pure functions |
| `test/data/book_downloader_test.dart` | Create | `MockClient` + `FakeDownloadStorage` tests |
| `test/ui/download_notifier_test.dart` | Create | `DownloadNotifier` state-transition tests |
| `test/ui/book_details_sheet_test.dart` | Create | Widget tests for bottom sheet + format picker |

---

## Task 1: Add `media_store_plus` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependency to `pubspec.yaml`**

Open `pubspec.yaml` and add `media_store_plus` under `dependencies` (after `open_filex`):

```yaml
  open_filex: ^4.7.0
  media_store_plus: ^1.0.0
```

- [ ] **Step 2: Resolve packages**

```powershell
flutter pub get
```

Expected: resolves without version conflicts. If there is a conflict, run `flutter pub upgrade --major-versions` and check the `media_store_plus` pub.dev page for the compatible constraint.

- [ ] **Step 3: Commit**

```powershell
git add pubspec.yaml pubspec.lock
git commit -m "chore: add media_store_plus dependency"
```

---

## Task 2: Pure functions — `preferredLink`, `buildFileName`, `buildPathSegments`

**Files:**
- Create: `test/domain/download_utils_test.dart`
- Create: `lib/domain/download_utils.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/domain/download_utils_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

AcquisitionLink _link(String label) => AcquisitionLink(
      url: Uri.parse('https://example.com/${label.toLowerCase()}'),
      mimeType: 'application/octet-stream',
      formatLabel: label,
    );

BookEntry _book({
  String title = 'Book Title',
  List<String> authors = const ['Jane Doe'],
  String? series,
  double? seriesIndex,
  List<AcquisitionLink>? links,
}) =>
    BookEntry(
      title: title,
      authors: authors,
      series: series,
      seriesIndex: seriesIndex,
      acquisitionLinks: links ?? [_link('FB2')],
    );

void main() {
  // ── preferredLink ──────────────────────────────────────────────────────────

  group('preferredLink', () {
    test('empty list returns null', () {
      expect(preferredLink([]), isNull);
    });

    test('single link is returned directly', () {
      final link = _link('EPUB');
      expect(preferredLink([link]), same(link));
    });

    test('FB2.ZIP preferred over FB2 when both present', () {
      final fb2 = _link('FB2');
      final zip = _link('FB2.ZIP');
      final epub = _link('EPUB');
      expect(preferredLink([fb2, epub, zip]), same(zip));
    });

    test('FB2 returned when only FB2 present among multiple', () {
      final fb2 = _link('FB2');
      final epub = _link('EPUB');
      expect(preferredLink([epub, fb2]), same(fb2));
    });

    test('returns null when multiple links but no FB2 variant', () {
      expect(preferredLink([_link('EPUB'), _link('PDF')]), isNull);
    });
  });

  // ── buildFileName ──────────────────────────────────────────────────────────

  group('buildFileName', () {
    test('single author, series with integer index', () {
      final book = _book(series: 'Great Series', seriesIndex: 1.0);
      expect(
        buildFileName(book, _link('FB2')),
        'Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('two authors joined with comma', () {
      final book = _book(authors: ['Jane Doe', 'John Smith']);
      expect(
        buildFileName(book, _link('EPUB')),
        'Jane Doe, John Smith - Book Title.epub',
      );
    });

    test('three or more authors appends et al.', () {
      final book = _book(authors: ['A', 'B', 'C']);
      expect(buildFileName(book, _link('PDF')), 'A et al. - Book Title.pdf');
    });

    test('no authors — author segment omitted entirely', () {
      final book = _book(authors: []);
      expect(buildFileName(book, _link('FB2')), 'Book Title.fb2');
    });

    test('no series — series segment omitted', () {
      expect(buildFileName(_book(), _link('FB2')), 'Jane Doe - Book Title.fb2');
    });

    test('series with no index — no #index', () {
      final book = _book(series: 'My Series');
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - My Series - Book Title.fb2');
    });

    test('seriesIndex 1.0 formats as "1"', () {
      final book = _book(series: 'S', seriesIndex: 1.0);
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - S #1 - Book Title.fb2');
    });

    test('seriesIndex 1.5 formats as "1.5"', () {
      final book = _book(series: 'S', seriesIndex: 1.5);
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - S #1.5 - Book Title.fb2');
    });

    test('FB2.ZIP extension is fb2.zip', () {
      expect(buildFileName(_book(), _link('FB2.ZIP')), 'Jane Doe - Book Title.fb2.zip');
    });

    test('EPUB extension is epub', () {
      expect(buildFileName(_book(), _link('EPUB')), 'Jane Doe - Book Title.epub');
    });

    test('illegal chars in title replaced with _', () {
      final book = _book(title: 'Title: A/B*C');
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - Title_ A_B_C.fb2');
    });

    test('filename capped at 200 chars, extension preserved', () {
      final book = _book(title: 'T' * 300);
      final result = buildFileName(book, _link('FB2'));
      expect(result.length, lessThanOrEqualTo(200));
      expect(result.endsWith('.fb2'), isTrue);
    });
  });

  // ── buildPathSegments ──────────────────────────────────────────────────────

  group('buildPathSegments', () {
    const system = AppSettings(target: SystemDownloads());

    test('both flags off — empty list', () {
      expect(buildPathSegments(system, _book(series: 'S')), isEmpty);
    });

    test('author flag on — author segment added', () {
      const s = AppSettings(target: SystemDownloads(), createAuthorFolder: true);
      expect(buildPathSegments(s, _book()), ['Jane Doe']);
    });

    test('series flag on — series segment added', () {
      const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
      expect(buildPathSegments(s, _book(series: 'Great Series')), ['Great Series']);
    });

    test('both flags on — author then series', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(
        buildPathSegments(s, _book(series: 'Great Series')),
        ['Jane Doe', 'Great Series'],
      );
    });

    test('author flag on but authors empty — no folder created', () {
      const s = AppSettings(target: SystemDownloads(), createAuthorFolder: true);
      expect(buildPathSegments(s, _book(authors: [])), isEmpty);
    });

    test('series flag on but series null — no folder created', () {
      const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
      expect(buildPathSegments(s, _book()), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/domain/download_utils_test.dart
```

Expected: compile error — `download_utils.dart` not found.

- [ ] **Step 3: Create `lib/domain/download_utils.dart`**

```dart
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

/// Returns the preferred [AcquisitionLink] to download without showing a picker,
/// or null when a picker is required (multiple links, none is FB2 or FB2.ZIP).
/// Preference order: FB2.ZIP > FB2 > (null = picker needed).
AcquisitionLink? preferredLink(List<AcquisitionLink> links) {
  if (links.isEmpty) return null;
  if (links.length == 1) return links.first;
  final fb2zip = links.where((l) => l.formatLabel == 'FB2.ZIP').firstOrNull;
  if (fb2zip != null) return fb2zip;
  final fb2 = links.where((l) => l.formatLabel == 'FB2').firstOrNull;
  return fb2; // null when no FB2 variant → caller shows format picker
}

/// Builds the sanitized download filename for [entry] in [link]'s format.
/// Pattern: `<Authors> - [<Series> #<Index> - ]<Title>.<ext>`
/// Capped at 200 characters (truncates title segment, preserves extension).
String buildFileName(BookEntry entry, AcquisitionLink link) {
  final parts = <String>[];
  final authors = _authorString(entry.authors);
  if (authors != null) parts.add(authors);
  if (entry.series != null) {
    final idx = entry.seriesIndex;
    parts.add(idx != null
        ? '${entry.series} #${_formatIndex(idx)}'
        : entry.series!);
  }
  parts.add(entry.title);
  final ext = _formatExt(link.formatLabel);
  var name = _sanitize('${parts.join(' - ')}.$ext');
  if (name.length > 200) {
    final suffix = '.$ext';
    name = '${name.substring(0, 200 - suffix.length)}$suffix';
  }
  return name;
}

/// Returns the list of subdirectory segments to place between the storage root
/// and the filename, based on [settings]. Returns an empty list when no
/// folder-per-author/series data is available.
List<String> buildPathSegments(AppSettings settings, BookEntry entry) {
  final segments = <String>[];
  final authors = _authorString(entry.authors);
  if (settings.createAuthorFolder && authors != null) {
    segments.add(_sanitize(authors));
  }
  if (settings.createSeriesFolder && entry.series != null) {
    segments.add(_sanitize(entry.series!));
  }
  return segments;
}

String? _authorString(List<String> authors) {
  if (authors.isEmpty) return null;
  if (authors.length == 1) return authors.first;
  if (authors.length == 2) return '${authors[0]}, ${authors[1]}';
  return '${authors.first} et al.';
}

String _formatIndex(double idx) =>
    idx == idx.truncateToDouble() ? idx.toInt().toString() : idx.toString();

String _formatExt(String label) =>
    label == 'FB2.ZIP' ? 'fb2.zip' : label.toLowerCase();

String _sanitize(String s) => s
    .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/domain/download_utils_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/domain/download_utils.dart test/domain/download_utils_test.dart
git commit -m "feat(domain): add preferredLink, buildFileName, buildPathSegments"
```

---

## Task 3: `MediaStoreDownloadStorage`

No host-side unit tests — this class wraps Android platform channels and requires a device.

**Files:**
- Create: `lib/data/media_store_download_storage.dart`

- [ ] **Step 1: Create `lib/data/media_store_download_storage.dart`**

> **Note:** The exact method names below depend on the `media_store_plus` version installed.
> Run `flutter pub deps | findstr media_store_plus` to see the resolved version, then check
> the package's pub.dev README to verify `saveFile` and `checkFileExistence` signatures.
> Adjust the method calls and parameters if the installed version differs.

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:opds_browser/domain/repositories.dart';

class MediaStoreDownloadStorage implements DownloadStorage {
  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async {
    return await MediaStorePlugin.instance.checkFileExistence(
          fileName: fileName,
          dirType: DirType.download,
          dirName: DirName.download,
        ) ??
        false;
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    final data = await bytes.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final tempFile = File('${Directory.systemTemp.path}/$fileName');
    await tempFile.writeAsBytes(Uint8List.fromList(data));
    try {
      final uri = await MediaStorePlugin.instance.saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );
      return uri?.toString() ?? '';
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }
}
```

- [ ] **Step 2: Run analysis**

```powershell
flutter analyze
```

Expected: no issues. If `MediaStorePlugin`, `DirType`, or `DirName` are not found, check the
installed package's import path and class names — adjust the `import` statement and class
references accordingly.

- [ ] **Step 3: Commit**

```powershell
git add lib/data/media_store_download_storage.dart
git commit -m "feat(data): add MediaStoreDownloadStorage using media_store_plus"
```

---

## Task 4: `BookDownloader`

**Files:**
- Create: `test/data/book_downloader_test.dart`
- Create: `lib/data/book_downloader.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/data/book_downloader_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/book_downloader.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;
  final String writeResult;
  String? writtenFileName;
  List<String>? writtenSegments;

  FakeDownloadStorage({
    this.existsResult = false,
    this.writeResult = 'content://fake/1',
  });

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async =>
      existsResult;

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    writtenFileName = fileName;
    writtenSegments = pathSegments;
    await bytes.drain<void>();
    return writeResult;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

final _link = AcquisitionLink(
  url: Uri.parse('https://example.com/book.fb2'),
  mimeType: 'application/fb2',
  formatLabel: 'FB2',
);

final _book = BookEntry(
  title: 'Book Title',
  authors: ['Jane Doe'],
  acquisitionLinks: [_link],
);

const _settings = AppSettings(target: SystemDownloads());

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('file already exists — returns "already_exists" without HTTP call', () async {
    var httpCalled = false;
    final client = MockClient((_) async {
      httpCalled = true;
      return http.Response('', 200);
    });
    final storage = FakeDownloadStorage(existsResult: true);
    final downloader = BookDownloader(client, storage);

    final result = await downloader.download(_book, _link, _settings);

    expect(result, 'already_exists');
    expect(httpCalled, isFalse);
  });

  test('successful download — correct fileName and segments passed to storage', () async {
    final client = MockClient(
      (_) async => http.Response.bytes([1, 2, 3], 200),
    );
    final storage = FakeDownloadStorage(writeResult: 'content://uri/123');
    final downloader = BookDownloader(client, storage);

    final result = await downloader.download(_book, _link, _settings);

    expect(result, 'content://uri/123');
    expect(storage.writtenFileName, buildFileName(_book, _link));
    expect(storage.writtenSegments, isEmpty);
  });

  test('non-2xx response throws HttpStatusException', () async {
    final client = MockClient((_) async => http.Response('Not found', 404));
    final storage = FakeDownloadStorage();
    final downloader = BookDownloader(client, storage);

    await expectLater(
      downloader.download(_book, _link, _settings),
      throwsA(
        isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('SocketException throws NetworkException', () async {
    final client = MockClient(
      (_) async => throw const SocketException('Network is unreachable'),
    );
    final storage = FakeDownloadStorage();
    final downloader = BookDownloader(client, storage);

    await expectLater(
      downloader.download(_book, _link, _settings),
      throwsA(isA<NetworkException>()),
    );
  });

  test('path segments include author folder when flag is on', () async {
    final client = MockClient((_) async => http.Response.bytes([1], 200));
    final storage = FakeDownloadStorage();
    final downloader = BookDownloader(client, storage);
    const settings = AppSettings(
      target: SystemDownloads(),
      createAuthorFolder: true,
    );

    await downloader.download(_book, _link, settings);

    expect(storage.writtenSegments, ['Jane Doe']);
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/data/book_downloader_test.dart
```

Expected: compile error — `BookDownloader` not found.

- [ ] **Step 3: Create `lib/data/book_downloader.dart`**

```dart
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

class BookDownloader {
  BookDownloader(this._client, this._storage);

  final http.Client _client;
  final DownloadStorage _storage;

  static const _alreadyExists = 'already_exists';

  Future<String> download(
    BookEntry entry,
    AcquisitionLink link,
    AppSettings settings,
  ) async {
    final segments = buildPathSegments(settings, entry);
    final fileName = buildFileName(entry, link);

    if (await _storage.exists(segments, fileName)) {
      return _alreadyExists;
    }

    late http.StreamedResponse response;
    try {
      final request = http.Request('GET', link.url)
        ..headers['User-Agent'] = 'OpdsBrowser/1.0';
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on TimeoutException {
      throw const NetworkException('Connection timed out');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpStatusException(
        response.statusCode,
        'HTTP ${response.statusCode}',
      );
    }

    return _storage.write(segments, fileName, response.stream);
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/data/book_downloader_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/book_downloader.dart test/data/book_downloader_test.dart
git commit -m "feat(data): add BookDownloader with HTTP streaming and DownloadStorage"
```

---

## Task 5: `DownloadState`, `DownloadNotifier`, and new providers

**Files:**
- Create: `test/ui/download_notifier_test.dart`
- Modify: `lib/ui/providers.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/ui/download_notifier_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;
  final String writeResult;

  FakeDownloadStorage({
    this.existsResult = false,
    this.writeResult = 'content://fake/1',
  });

  @override
  Future<bool> exists(List<String> p, String f) async => existsResult;

  @override
  Future<String> write(List<String> p, String f, Stream<List<int>> b) async {
    await b.drain<void>();
    return writeResult;
  }
}

// ── Container builder ─────────────────────────────────────────────────────────

ProviderContainer _makeContainer({
  required MockClient client,
  bool storageExists = false,
  String storageWriteResult = 'content://fake/1',
}) {
  final c = ProviderContainer(overrides: [
    httpClientProvider.overrideWith((ref) => client),
    downloadStorageProvider.overrideWith(
      (ref) => FakeDownloadStorage(
        existsResult: storageExists,
        writeResult: storageWriteResult,
      ),
    ),
  ]);
  addTearDown(c.dispose);
  return c;
}

// ── Test data ─────────────────────────────────────────────────────────────────

final _linkUrl = Uri.parse('https://example.com/book.fb2');

final _book = BookEntry(
  title: 'Book Title',
  authors: ['Jane Doe'],
  acquisitionLinks: [
    AcquisitionLink(
      url: _linkUrl,
      mimeType: 'application/fb2',
      formatLabel: 'FB2',
    ),
  ],
);

const _settings = AppSettings(target: SystemDownloads());

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('initial state is DownloadIdle', () {
    final c = _makeContainer(client: MockClient((_) async => http.Response('', 200)));
    expect(c.read(downloadNotifierProvider(_linkUrl)), isA<DownloadIdle>());
  });

  test('start() transitions to DownloadDone on success', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      storageWriteResult: 'content://result/42',
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final state = c.read(downloadNotifierProvider(_linkUrl));
    expect(state, isA<DownloadDone>());
    final done = state as DownloadDone;
    expect(done.alreadyExisted, isFalse);
    expect(done.contentUri, 'content://result/42');
    expect(done.fileName, isNotEmpty);
  });

  test('start() with already-existing file → DownloadDone(alreadyExisted: true)', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response('', 200)),
      storageExists: true,
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final done = c.read(downloadNotifierProvider(_linkUrl)) as DownloadDone;
    expect(done.alreadyExisted, isTrue);
    expect(done.contentUri, '');
  });

  test('start() with non-2xx response → DownloadFailed', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response('Not found', 404)),
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    expect(c.read(downloadNotifierProvider(_linkUrl)), isA<DownloadFailed>());
    final failed = c.read(downloadNotifierProvider(_linkUrl)) as DownloadFailed;
    expect(failed.message, contains('404'));
  });

  test('start() is a no-op when already DownloadInProgress', () async {
    var callCount = 0;
    final completer = Completer<http.Response>();
    final c = _makeContainer(
      client: MockClient((_) {
        callCount++;
        return completer.future;
      }),
    );

    final notifier = c.read(downloadNotifierProvider(_linkUrl).notifier);
    // Kick off first download — does not await (it's waiting for completer)
    final firstFuture = notifier.start(_book, _settings);
    // Yield so the first start() can run up to the await point
    await Future<void>.microtask(() {});
    expect(c.read(downloadNotifierProvider(_linkUrl)), isA<DownloadInProgress>());

    // Second call — should be no-op
    await notifier.start(_book, _settings);
    expect(callCount, 1);

    // Let the first download finish
    completer.complete(http.Response.bytes([1], 200));
    await firstFuture;
  });

  test('lastDownloadResultProvider is set on successful completion', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    expect(c.read(lastDownloadResultProvider), isA<DownloadDone>());
  });

  test('lastDownloadResultProvider is set when file already existed', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response('', 200)),
      storageExists: true,
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final result = c.read(lastDownloadResultProvider);
    expect(result, isA<DownloadDone>());
    expect((result as DownloadDone).alreadyExisted, isTrue);
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/ui/download_notifier_test.dart
```

Expected: compile error — `DownloadIdle`, `DownloadNotifier`, `httpClientProvider`, etc. not found.

- [ ] **Step 3: Add `DownloadState`, `DownloadNotifier`, and new providers to `lib/ui/providers.dart`**

Add the following imports at the top of the existing imports block in `lib/ui/providers.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:opds_browser/data/book_downloader.dart';
import 'package:opds_browser/data/media_store_download_storage.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/opds_client.dart';
```

Update the existing `downloadStorageProvider` — replace:

```dart
final downloadStorageProvider = Provider<DownloadStorage?>((ref) {
  final target = ref.watch(settingsProvider).value?.target;
  return switch (target) {
    CustomSafFolder(uriString: final uri) => SafDownloadStorage(uri),
    _ => null,
  };
});
```

With:

```dart
final downloadStorageProvider = Provider<DownloadStorage?>((ref) {
  final target = ref.watch(settingsProvider).value?.target;
  return switch (target) {
    SystemDownloads() => MediaStoreDownloadStorage(),
    CustomSafFolder(uriString: final uri) => SafDownloadStorage(uri),
    null => null,
  };
});
```

Then append the following after the existing `downloadStorageProvider`:

```dart
// ── Download ──────────────────────────────────────────────────────────────────

sealed class DownloadState {
  const DownloadState();
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class DownloadInProgress extends DownloadState {
  const DownloadInProgress();
}

class DownloadDone extends DownloadState {
  const DownloadDone({
    required this.contentUri,
    required this.fileName,
    required this.alreadyExisted,
  });

  final String contentUri;
  final String fileName;
  final bool alreadyExisted;
}

class DownloadFailed extends DownloadState {
  const DownloadFailed(this.message);
  final String message;
}

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final bookDownloaderProvider = Provider<BookDownloader>((ref) => BookDownloader(
      ref.watch(httpClientProvider),
      ref.watch(downloadStorageProvider) ?? MediaStoreDownloadStorage(),
    ));

final lastDownloadResultProvider = StateProvider<DownloadDone?>((ref) => null);

class DownloadNotifier extends Notifier<DownloadState> {
  late Uri _linkUrl;

  void _setUrl(Uri url) => _linkUrl = url;

  @override
  DownloadState build() => const DownloadIdle();

  Future<void> start(BookEntry entry, AppSettings settings) async {
    if (state is DownloadInProgress) return;
    state = const DownloadInProgress();

    final link = entry.acquisitionLinks.firstWhere((l) => l.url == _linkUrl);
    final fileName = buildFileName(entry, link);

    try {
      final result = await ref
          .read(bookDownloaderProvider)
          .download(entry, link, settings);
      final done = result == 'already_exists'
          ? DownloadDone(contentUri: '', fileName: fileName, alreadyExisted: true)
          : DownloadDone(
              contentUri: result,
              fileName: fileName,
              alreadyExisted: false,
            );
      ref.read(lastDownloadResultProvider.notifier).state = done;
      state = done;
    } on OpdsException catch (e) {
      state = DownloadFailed(_mapError(e));
    } catch (e) {
      state = DownloadFailed('Unexpected error: $e');
    }
  }
}

final downloadNotifierProvider =
    NotifierProvider.family<DownloadNotifier, DownloadState, Uri>(
  (url) => DownloadNotifier().._setUrl(url),
);

String _mapError(OpdsException e) => switch (e) {
      NetworkException() =>
        'Network error. Check your connection and try again.',
      HttpStatusException(statusCode: 404) =>
        'This folder no longer exists on the server.',
      HttpStatusException(statusCode: 401 || 403) =>
        'This catalogue requires authentication, which is not supported.',
      HttpStatusException(statusCode: final code) => 'Server error (HTTP $code).',
      ParseException() => 'The server response is not a valid OPDS feed.',
      UnsupportedProtocolException() => 'Not a supported OPDS catalogue.',
    };
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/ui/download_notifier_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/download_notifier_test.dart
git commit -m "feat(ui): add DownloadState, DownloadNotifier, httpClientProvider, bookDownloaderProvider"
```

---

## Task 6: `BookDetailsSheet`

**Files:**
- Create: `test/ui/book_details_sheet_test.dart`
- Create: `lib/ui/book_details_sheet.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/ui/book_details_sheet_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;

  FakeDownloadStorage({this.existsResult = false});

  @override
  Future<bool> exists(List<String> p, String f) async => existsResult;

  @override
  Future<String> write(List<String> p, String f, Stream<List<int>> b) async {
    await b.drain<void>();
    return 'content://fake/1';
  }
}

// ── Fake settings notifier ────────────────────────────────────────────────────

class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  FakeSettingsNotifier({AppSettings initial = const AppSettings(target: SystemDownloads())})
      : _initial = initial;

  @override
  Future<AppSettings> build() async => _initial;
}

// ── Helper ────────────────────────────────────────────────────────────────────

AcquisitionLink _link(String label) => AcquisitionLink(
      url: Uri.parse('https://example.com/${label.toLowerCase()}'),
      mimeType: 'application/octet-stream',
      formatLabel: label,
    );

Widget _buildApp({
  required BookEntry entry,
  required MockClient mockClient,
  bool storageExists = false,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => FakeSettingsNotifier()),
      httpClientProvider.overrideWith((ref) => mockClient),
      downloadStorageProvider.overrideWith(
        (ref) => FakeDownloadStorage(existsResult: storageExists),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: BookDetailsSheet(entry: entry)),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('BookDetailsSheet rendering', () {
    testWidgets('renders title, authors, series, and summary', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        series: 'Great Series',
        seriesIndex: 1.0,
        summary: 'A great summary.',
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Book Title'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Great Series #1'), findsOneWidget);
      expect(find.text('A great summary.'), findsOneWidget);
    });

    testWidgets('renders cover placeholder when no coverUrl', (tester) async {
      final entry = BookEntry(
        title: 'T',
        authors: [],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.book), findsWidgets);
    });
  });

  group('Download button — direct download (FB2.ZIP present)', () {
    testWidgets('tapping Download starts download without showing picker',
        (tester) async {
      var httpCalled = false;
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('FB2.ZIP')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async {
            httpCalled = true;
            return http.Response.bytes([1, 2, 3], 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(httpCalled, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Download button — format picker (no FB2)', () {
    testWidgets('tapping Download shows "Choose format" dialog', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.text('Choose format'), findsOneWidget);
      expect(find.text('EPUB'), findsWidgets);
      expect(find.text('PDF'), findsWidgets);
    });

    testWidgets('choosing a format from picker starts download', (tester) async {
      var httpCalled = false;
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async {
            httpCalled = true;
            return http.Response.bytes([1, 2, 3], 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      // Tap EPUB in the dialog
      await tester.tap(find.text('EPUB').last);
      await tester.pumpAndSettle();

      expect(httpCalled, isTrue);
    });
  });

  group('Secondary format rows', () {
    testWidgets('all format rows are visible', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2'), _link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FB2'), findsOneWidget);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('tapping a secondary row starts download for that format',
        (tester) async {
      Uri? requestedUrl;
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2'), _link('EPUB')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((request) async {
            requestedUrl = request.url;
            return http.Response.bytes([1], 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EPUB'));
      await tester.pumpAndSettle();

      expect(requestedUrl?.toString(), contains('epub'));
    });
  });

  group('DownloadInProgress state', () {
    testWidgets('spinner replaces Download button while downloading', (tester) async {
      final completer = Completer<http.Response>();
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) => completer.future),
        ),
      );
      await tester.pumpAndSettle();

      // Start download (don't await)
      unawaited(tester.tap(find.text('Download')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      completer.complete(http.Response.bytes([1], 200));
      await tester.pumpAndSettle();
    });
  });

  group('DownloadFailed snackbar', () {
    testWidgets('shows error snackbar with Retry action on failure', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response('Error', 500)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/ui/book_details_sheet_test.dart
```

Expected: compile error — `BookDetailsSheet` not found.

- [ ] **Step 3: Create `lib/ui/book_details_sheet.dart`**

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/providers.dart';

class BookDetailsSheet extends ConsumerStatefulWidget {
  const BookDetailsSheet({required this.entry, super.key});

  final BookEntry entry;

  @override
  ConsumerState<BookDetailsSheet> createState() => _BookDetailsSheetState();
}

class _BookDetailsSheetState extends ConsumerState<BookDetailsSheet> {
  Uri? _activeDownloadUrl;

  Uri get _defaultWatchUrl =>
      (preferredLink(widget.entry.acquisitionLinks) ??
              widget.entry.acquisitionLinks.first)
          .url;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const AppSettings(target: SystemDownloads());
    final watchUrl = _activeDownloadUrl ?? _defaultWatchUrl;
    final downloadState = ref.watch(downloadNotifierProvider(watchUrl));
    final isDownloading = downloadState is DownloadInProgress;

    ref.listen(downloadNotifierProvider(watchUrl), (_, state) {
      if (state is DownloadFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${state.message}'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => ref
                  .read(downloadNotifierProvider(watchUrl).notifier)
                  .start(widget.entry, settings),
            ),
          ),
        );
      }
    });

    final entry = widget.entry;
    final preferred = preferredLink(entry.acquisitionLinks);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(
                width: 120,
                height: 170,
                child: entry.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: entry.coverUrl!.toString(),
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const Icon(Icons.book, size: 48),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.book, size: 48),
                      )
                    : const Icon(Icons.book, size: 48),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              entry.title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (entry.authors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.authors.join(', ')),
            ],
            if (entry.series != null) ...[
              const SizedBox(height: 4),
              Text(_seriesText(entry)),
            ],
            if (entry.summary != null) ...[
              const SizedBox(height: 8),
              Text(entry.summary!),
            ],
            const Divider(height: 24),
            Center(
              child: isDownloading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () =>
                          _onDownloadTap(context, entry, preferred, settings),
                      child: const Text('Download'),
                    ),
            ),
            const SizedBox(height: 8),
            ...entry.acquisitionLinks.map(
              (link) => ListTile(
                title: Text(link.formatLabel),
                onTap: isDownloading
                    ? null
                    : () {
                        setState(() => _activeDownloadUrl = link.url);
                        ref
                            .read(downloadNotifierProvider(link.url).notifier)
                            .start(entry, settings);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDownloadTap(
    BuildContext context,
    BookEntry entry,
    AcquisitionLink? preferred,
    AppSettings settings,
  ) async {
    if (preferred != null) {
      setState(() => _activeDownloadUrl = preferred.url);
      ref
          .read(downloadNotifierProvider(preferred.url).notifier)
          .start(entry, settings);
    } else {
      final chosen =
          await _showFormatPicker(context, entry.acquisitionLinks);
      if (chosen == null || !mounted) return;
      setState(() => _activeDownloadUrl = chosen.url);
      ref
          .read(downloadNotifierProvider(chosen.url).notifier)
          .start(entry, settings);
    }
  }

  Future<AcquisitionLink?> _showFormatPicker(
    BuildContext context,
    List<AcquisitionLink> links,
  ) {
    return showDialog<AcquisitionLink>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: links
              .map(
                (l) => TextButton(
                  onPressed: () => Navigator.of(ctx).pop(l),
                  child: Text(l.formatLabel),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _seriesText(BookEntry entry) {
    final idx = entry.seriesIndex;
    if (idx == null) return entry.series!;
    final idxStr =
        idx == idx.truncateToDouble() ? idx.toInt().toString() : idx.toString();
    return '${entry.series} #$idxStr';
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/ui/book_details_sheet_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/book_details_sheet.dart test/ui/book_details_sheet_test.dart
git commit -m "feat(ui): add BookDetailsSheet with format picker and download state"
```

---

## Task 7: Wire `BrowseScreen` — `onTap` + completion snackbar

**Files:**
- Modify: `lib/ui/browse_screen.dart`

- [ ] **Step 1: Add `onTap` to `_BookEntryTile`**

In `lib/ui/browse_screen.dart`, find the `_BookEntryTile` `build` method. The current `ListTile` has no `onTap`. Add it:

Find this block in `_BookEntryTile.build()`:

```dart
    return ListTile(
      leading: SizedBox(
```

Replace with (the full `ListTile` call including the new `onTap`):

```dart
    return ListTile(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => BookDetailsSheet(entry: entry),
      ),
      leading: SizedBox(
```

Also add the import for `BookDetailsSheet` at the top of `browse_screen.dart`:

```dart
import 'package:opds_browser/ui/book_details_sheet.dart';
```

- [ ] **Step 2: Add completion snackbar listener to `_BrowseContent`**

In `_BrowseContent.build()`, add a `ref.listen` call right after the opening of the `build` method body (before the `return`), plus the required imports.

Add these imports to `browse_screen.dart`:

```dart
import 'package:open_filex/open_filex.dart';
```

Then in `_BrowseContent.build()`, add before `return Scaffold(...)`:

```dart
    ref.listen(lastDownloadResultProvider, (_, result) {
      if (result == null) return;
      ref.read(lastDownloadResultProvider.notifier).state = null;
      final msg = result.alreadyExisted
          ? 'Already downloaded: ${result.fileName}'
          : 'Downloaded: ${result.fileName}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: result.alreadyExisted
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => OpenFilex.open(result.contentUri),
                ),
        ),
      );
    });
```

- [ ] **Step 3: Run analysis**

```powershell
flutter analyze
```

Expected: no issues.

- [ ] **Step 4: Update browse_screen.dart tests to cover onTap**

In `test/ui/browse_screen_test.dart`, add a test that verifies tapping a book entry row opens a bottom sheet. Add to the existing test file (find a suitable `group`):

```dart
testWidgets('tapping a book entry tile opens BookDetailsSheet', (tester) async {
  // Re-use the existing test scaffold pattern from this file.
  // Build with a feed that contains a BookEntry.
  final feed = ParsedFeed(
    title: 'Feed',
    entries: [
      BookEntry(
        title: 'My Book',
        authors: ['Author'],
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/book.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      ),
    ],
  );
  // Use the same ProviderContainer override pattern already established
  // in this test file to inject a feed with a BookEntry.
  // (Follow the pattern used in the existing "renders book entries" test.)
  //
  // After pumping, tap the book row and verify the sheet appears:
  await tester.tap(find.text('My Book'));
  await tester.pumpAndSettle();
  expect(find.byType(BookDetailsSheet), findsOneWidget);
});
```

> **Note:** The exact widget test helper in `browse_screen_test.dart` varies — follow the existing
> `buildApp`/`ProviderContainer` pattern already in that file and inject a feed containing a
> `BookEntry`. The assertion `find.byType(BookDetailsSheet)` verifies the tap opens the sheet.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/browse_screen.dart test/ui/browse_screen_test.dart
git commit -m "feat(ui): wire BookDetailsSheet tap and download completion snackbar in BrowseScreen"
```

---

## Task 8: Quality gate

**Files:** none (verification only)

- [ ] **Step 1: Run the full quality gate**

```powershell
dart run tool/check.dart
```

Expected output ends with:
```
flutter analyze ... No issues found!
flutter test   ... All tests passed!
```

- [ ] **Step 2: Fix any issues**

Common causes:
- `strict-inference`: add explicit type annotations where Dart can't infer (e.g., `<int>[]`)
- `strict-casts`: replace `as T` with an `is T` guard
- Unused imports: remove
- `open_filex` import not needed in `browse_screen.dart` if it's only used via `OpenFilex.open` — verify the import is actually used

- [ ] **Step 3: Commit any fixes**

```powershell
git add -A
git commit -m "fix: resolve analysis issues from step 9"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| `preferredLink` — FB2.ZIP > FB2, null when no FB2 (§9.1) | Task 2 |
| `buildFileName` — pattern, author/series logic, sanitization, 200-char cap (§9.2) | Task 2 |
| `buildPathSegments` — author/series flags, no "Unknown" fallbacks (§9.3) | Task 2 |
| `MediaStoreDownloadStorage` — exists + write via MediaStore Downloads (§10.1) | Task 3 |
| `downloadStorageProvider` updated — `SystemDownloads` → `MediaStoreDownloadStorage` | Task 5 |
| `BookDownloader` — HTTP GET, 20s timeout, User-Agent, skip-existing, NetworkException/HttpStatusException (§9.4) | Task 4 |
| `httpClientProvider`, `bookDownloaderProvider` | Task 5 |
| `DownloadState` sealed class (Idle/InProgress/Done/Failed) | Task 5 |
| `DownloadNotifier.family` non-autoDispose, keyed by link URL | Task 5 |
| `lastDownloadResultProvider` — written by notifier, consumed by `_BrowseContent` | Tasks 5 + 7 |
| `BookDetailsSheet` — cover, title, authors, series, summary | Task 6 |
| Download button — FB2.ZIP direct, no-FB2 picker (§9.1) | Task 6 |
| Secondary format rows always visible | Task 6 |
| `DownloadInProgress` spinner replaces button | Task 6 |
| `DownloadFailed` snackbar with Retry in sheet (§9.4) | Task 6 |
| `_BookEntryTile.onTap` → `showModalBottomSheet` | Task 7 |
| Completion snackbar "Downloaded X" with Open action on `_BrowseContent` (§9.4) | Task 7 |
| "Already downloaded" snackbar (no Open action) (§9.3) | Task 7 |
| `open_filex` — Open action calls `OpenFilex.open(contentUri)` | Task 7 |
| Quality gate: `flutter analyze` clean + `flutter test` green (§13.5) | Task 8 |

**Placeholder scan:** No TBDs, TODOs, or "implement later" phrases present.

**Type consistency:**
- `DownloadNotifier._setUrl(Uri)` defined Task 5, used in family factory Task 5 ✓
- `DownloadNotifier.start(BookEntry, AppSettings)` defined Task 5, called in Task 6 ✓
- `downloadNotifierProvider(Uri)` defined Task 5, used in Tasks 6 + 7 ✓
- `lastDownloadResultProvider` defined as `StateProvider<DownloadDone?>` Task 5, read/set in Tasks 5 + 7 ✓
- `buildFileName(BookEntry, AcquisitionLink)` defined Task 2, used in Tasks 4 + 5 ✓
- `buildPathSegments(AppSettings, BookEntry)` defined Task 2, used in Task 4 ✓
- `preferredLink(List<AcquisitionLink>)` defined Task 2, used in Tasks 5 + 6 ✓
- `DownloadDone.contentUri`, `.fileName`, `.alreadyExisted` defined Task 5, used in Tasks 5 + 7 ✓

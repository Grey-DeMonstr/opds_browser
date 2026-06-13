# Single-Book Download + Bottom Sheet — Design Spec

**Step:** 9 of 11  
**Date:** 2026-06-13  
**Status:** Approved

---

## Overview

Implement single-book download end-to-end: format selection logic, file naming, destination path
building, a `BookDownloader` data class, `MediaStoreDownloadStorage` for the system Downloads
folder, a `DownloadNotifier` family for per-link download state, and the book details bottom sheet
UI with a format picker and snackbar wiring on `BrowseScreen`.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/domain/download_utils.dart` | Create | `preferredLink`, `buildFileName`, `buildPathSegments` pure functions |
| `lib/data/book_downloader.dart` | Create | `BookDownloader(http.Client, DownloadStorage)` — HTTP fetch + `DownloadStorage.write` |
| `lib/data/media_store_download_storage.dart` | Create | `MediaStoreDownloadStorage` via `media_store_plus` |
| `lib/ui/providers.dart` | Modify | Add `httpClientProvider`, `bookDownloaderProvider`, `DownloadState`, `DownloadNotifier` family, `downloadNotifierProvider`, `lastDownloadResultProvider`; update `downloadStorageProvider` |
| `lib/ui/book_details_sheet.dart` | Create | `BookDetailsSheet` modal bottom sheet widget + format picker dialog |
| `lib/ui/browse_screen.dart` | Modify | `_BookEntryTile` gains `onTap`; `_BrowseContent` listens to `lastDownloadResultProvider` for snackbar |
| `pubspec.yaml` | Modify | Add `media_store_plus` dependency |
| `test/domain/download_utils_test.dart` | Create | Unit tests for all three pure functions |
| `test/data/book_downloader_test.dart` | Create | Tests with `MockClient` + `FakeDownloadStorage` |
| `test/ui/download_notifier_test.dart` | Create | Tests for `DownloadNotifier` state transitions |
| `test/ui/book_details_sheet_test.dart` | Create | Widget tests for bottom sheet and format picker |

---

## 1. Pure functions (`lib/domain/download_utils.dart`)

### `preferredLink`

```dart
AcquisitionLink? preferredLink(List<AcquisitionLink> links)
```

- Single link → return it directly.
- Multiple links, FB2 format present → prefer `FB2.ZIP` over `FB2`; return the preferred one.
  The remaining formats are still shown as secondary rows in the sheet.
- Multiple links, no FB2 (`FB2` or `FB2.ZIP`) → return null (caller must show format picker).

### `buildFileName`

```dart
String buildFileName(BookEntry entry, AcquisitionLink link)
```

Pattern: `<Authors> - [<Series> #<Index> - ]<Title>.<ext>`

- **Authors segment:** single author → use as-is; two authors → joined with `", "`; more than two → first author + `" et al."`. If `entry.authors` is empty → omit the authors segment entirely (no "Unknown" placeholder).
- **Series segment:** included only when `entry.series != null`. Format: `<series> #<index>` when `seriesIndex != null`, else just `<series>`. Index formatted without trailing `.0` (e.g. `1.0` → `1`, `1.5` → `1.5`).
- **Extension:** derived from `link.formatLabel`: lowercased, with `FB2.ZIP` → `fb2.zip` as a special case; all others are simply `label.toLowerCase()`.
- **Sanitization** (applied to the full assembled filename): replace `\ / : * ? " < > |` and ASCII control characters with `_`; collapse runs of whitespace to a single space; trim; cap total length at 200 characters by truncating the title segment.

### `buildPathSegments`

```dart
List<String> buildPathSegments(AppSettings settings, BookEntry entry)
```

Returns the folder segments placed between the storage root and the filename.

- If `settings.createAuthorFolder` is true and authors are non-empty → prepend author segment (same string as used in filename, sanitized).
- If `settings.createSeriesFolder` is true and `entry.series != null` → append series segment (sanitized series name).
- Segments are omitted when the relevant data is absent — no "Unknown author" or "Unknown series" folders.
- Returns an empty list when both flags are false or data is missing.

All three functions are pure Dart with no platform dependencies and must be fully tested on host.

---

## 2. Data layer

### `MediaStoreDownloadStorage` (`lib/data/media_store_download_storage.dart`)

Implements `DownloadStorage` using the `media_store_plus` package (Android MediaStore Downloads
collection, API 29+).

**`exists(pathSegments, fileName)`** — queries MediaStore for a file with
`RELATIVE_PATH = DIRECTORY_DOWNLOADS/<segments.join('/')>` and `DISPLAY_NAME = fileName`.
Returns true if a matching row is found.

**`write(pathSegments, fileName, bytes)`** — collects the byte stream, then inserts into MediaStore
with:
- `RELATIVE_PATH = DIRECTORY_DOWNLOADS/<segments.join('/')>`
- `DISPLAY_NAME = fileName`
- `MIME_TYPE = application/octet-stream`

Returns the content URI string of the newly created file.

No host-side unit tests (platform channel; requires device). Consistent with `SafDownloadStorage`.

### `downloadStorageProvider` update

The existing `downloadStorageProvider` in `providers.dart` currently returns `null` for
`SystemDownloads`. Updated switch:

```dart
switch (target) {
  SystemDownloads() => MediaStoreDownloadStorage(),
  CustomSafFolder(uriString: final uri) => SafDownloadStorage(uri),
  null => null,  // settingsProvider not yet loaded
}
```

### `BookDownloader` (`lib/data/book_downloader.dart`)

```dart
class BookDownloader {
  BookDownloader(this._client, this._storage);
  final http.Client _client;
  final DownloadStorage _storage;

  Future<String> download(
    BookEntry entry,
    AcquisitionLink link,
    AppSettings settings,
  ) async { ... }
}
```

**Algorithm:**
1. `segments = buildPathSegments(settings, entry)`
2. `fileName = buildFileName(entry, link)`
3. If `await _storage.exists(segments, fileName)` → return sentinel `"already_exists"`
4. HTTP GET `link.url` with 20 s timeout; header `User-Agent: OpdsBrowser/1.0`
5. Non-2xx response → throw `HttpStatusException`
6. Network/timeout failure → throw `NetworkException`
7. `return await _storage.write(segments, fileName, response.stream)`

Returns the content URI string on success, or `"already_exists"` when the file was skipped.

Fully unit-testable: `MockClient` (from `package:http`) for HTTP, `FakeDownloadStorage` for storage.

---

## 3. State management (`lib/ui/providers.dart` additions)

### `DownloadState`

```dart
sealed class DownloadState {}
class DownloadIdle     extends DownloadState {}
class DownloadInProgress extends DownloadState {}
class DownloadDone     extends DownloadState {
  final String contentUri;
  final String fileName;
  final bool alreadyExisted;
}
class DownloadFailed   extends DownloadState { final String message; }
```

### `DownloadNotifier`

`AutoDisposeNotifier<DownloadState>` family keyed by `Uri` (the `AcquisitionLink.url`).
Starts in `DownloadIdle`. Exposes:

```dart
Future<void> start(BookEntry entry, AppSettings settings) async { ... }
```

- Transitions to `DownloadInProgress`, calls `bookDownloaderProvider.download(...)`.
- On success: sets `lastDownloadResultProvider` to a `DownloadDone`, transitions to `DownloadDone`.
- On `OpdsException`: transitions to `DownloadFailed` with a user-facing message (using the error
  mapping from spec §12).
- `"already_exists"` sentinel → `DownloadDone(alreadyExisted: true, contentUri: "", fileName: ...)`.

### New providers

```dart
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final bookDownloaderProvider = Provider<BookDownloader>((ref) =>
    BookDownloader(
      ref.watch(httpClientProvider),
      ref.watch(downloadStorageProvider) ?? MediaStoreDownloadStorage(),
    ));

final downloadNotifierProvider = AutoDisposeNotifierProvider
    .family<DownloadNotifier, DownloadState, Uri>(...);

final lastDownloadResultProvider = StateProvider<DownloadDone?>((ref) => null);
```

---

## 4. UI

### `BookDetailsSheet` (`lib/ui/book_details_sheet.dart`)

Opened via `showModalBottomSheet(isScrollControlled: true, ...)` from `_BookEntryTile.onTap`.
Receives a `BookEntry`. Watches `settingsProvider` for `AppSettings`.

**Layout (scrollable `SingleChildScrollView` → `Column`):**
1. Cover image: `CachedNetworkImage`, ~120×170, placeholder `Icon(Icons.book)`
2. Title (bold, wrapping)
3. Authors line
4. Series line (`"<Series> #<index>"`) if present
5. Summary (scrollable within the column) if present
6. `Divider`
7. **Download button** (`ElevatedButton`, label `"Download"`):
   - `preferredLink` returns a link → call `notifier.start(entry, settings)` immediately
   - `preferredLink` returns null → `await _showFormatPicker(context, links)`, then call `notifier.start`
   - While `DownloadInProgress`: replace button with `CircularProgressIndicator()`
8. **Secondary format rows**: one `ListTile` per `AcquisitionLink` (showing `formatLabel`); always visible; tapping calls `notifier.start(entry, settings)` with that specific link

Download state is watched via `ref.watch(downloadNotifierProvider(link.url))` where `link` is the
preferred link (or the first link when picker is needed).

### Format picker dialog

```dart
Future<AcquisitionLink?> _showFormatPicker(
    BuildContext context, List<AcquisitionLink> links)
```

`AlertDialog` with title `"Choose format"` and a `Column` of `TextButton`s, one per link (label =
`formatLabel`). Returns the chosen link or null on dismiss.

### Snackbar wiring in `_BrowseContent`

`_BrowseContent` adds:

```dart
ref.listen(lastDownloadResultProvider, (_, result) {
  if (result == null) return;
  ref.read(lastDownloadResultProvider.notifier).state = null;
  final msg = result.alreadyExisted
      ? 'Already downloaded: ${result.fileName}'
      : 'Downloaded: ${result.fileName}';
  final snackBar = result.alreadyExisted
      ? SnackBar(content: Text(msg))
      : SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFilex.open(result.contentUri),
          ),
        );
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
});
```

On `DownloadFailed`: a separate `ref.listen` on `downloadNotifierProvider` in the sheet shows
`"Download failed: <message>"` with a **Retry** `SnackBarAction`.

### `_BookEntryTile` change in `browse_screen.dart`

Add:
```dart
onTap: () => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => BookDetailsSheet(entry: entry),
),
```

---

## 5. Testing strategy

### `test/domain/download_utils_test.dart`

`preferredLink`:
- Single link → returned
- FB2 + FB2.ZIP present → FB2.ZIP preferred
- FB2 only → returned directly
- No FB2, multiple links → null
- Empty list → null

`buildFileName`:
- Single author, series with index
- Two authors joined
- Three authors → "et al."
- No authors → no author segment
- No series → series segment omitted
- `seriesIndex == null` → no `#index`
- `1.0` → `"1"`, `1.5` → `"1.5"`
- Extension mapping: `FB2.ZIP` → `fb2.zip`, `EPUB` → `epub`
- Sanitization: illegal chars → `_`
- Filename capped at 200 chars

`buildPathSegments`:
- Both flags off → empty list
- Author flag on, authors present → `["Jane Doe"]`
- Series flag on, series present → `["Great Series"]`
- Both on → `["Jane Doe", "Great Series"]`
- Author flag on, no authors → empty (no "Unknown" folder)
- Series flag on, series null → omitted

### `test/data/book_downloader_test.dart`

- File already exists → returns `"already_exists"`, no HTTP call
- Successful download → correct segments/filename passed to storage, content URI returned
- Non-2xx response → throws `HttpStatusException`
- Network error → throws `NetworkException`

Uses `MockClient` and a `FakeDownloadStorage` that tracks `exists`/`write` calls.

### `test/ui/download_notifier_test.dart`

- Initial state is `DownloadIdle`
- `start()` transitions through `DownloadInProgress` → `DownloadDone`
- `start()` on already-existing file → `DownloadDone(alreadyExisted: true)`
- `start()` on network error → `DownloadFailed`
- `lastDownloadResultProvider` is set on completion

### `test/ui/book_details_sheet_test.dart`

- Renders cover placeholder, title, authors, series, summary
- FB2.ZIP present → single Download button, no picker shown on tap
- No FB2 → tapping Download opens format picker dialog; choosing a format triggers download
- Secondary format rows visible; tapping one starts download for that format
- `DownloadInProgress` → progress indicator replaces button
- `DownloadDone(alreadyExisted: true)` → snackbar "Already downloaded: …"
- `DownloadFailed` → snackbar "Download failed: …" with Retry action

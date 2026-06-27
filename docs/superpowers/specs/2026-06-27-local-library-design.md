# Local Library Management — Design Spec

**Date:** 2026-06-27
**Status:** Approved

## Overview

Add a "Manage local library" feature that lets the user browse, inspect, and correct FB2 books stored in their download folder. The feature is broken into four incremental steps:

1. Browse the library folder tree and display cached FB2 metadata (title, author, series, series #)
2. Edit book metadata in-place and persist changes back to the FB2/fb2.zip file
3. Validate all books against the expected filesystem layout (Author / Series? / book)
4. Fix invalid books by writing metadata from the folder path

---

## Section 1: Entry Point, Intro Screen, and Navigation

### Mandatory folder selection

A GoRouter redirect watches `settingsProvider`. If `AppSettings.target` is not a `CustomSafFolder` (first launch or after SAF permission revocation), the router redirects `/` to `/setup`.

The `/setup` screen shows a brief explanation ("Pick a folder where your books are stored") and a "Pick library folder" button that calls the existing `settingsProvider.pickCustomFolder()`. There is no back button. After a folder is picked the redirect clears and the user lands on the main screen.

### Cleanup: remove SystemDownloads

`SystemDownloads` is removed entirely:

- The `SystemDownloads` class is deleted from `entities.dart`
- All branches in `downloadStorageProvider`, `SettingsNotifier`, and `SafDownloadStorage` that switch on `SystemDownloads` are removed
- `SettingsScreen` simplifies to a single "Change folder" tile — no radio buttons
- `CLAUDE.md` and `docs/opds_browser_spec.md` are updated to reflect that `SystemDownloads` is gone and a custom SAF folder is always required

### Main screen button

A "Manage local library" `IconButton` (`Icons.local_library`) is added to the main screen's AppBar, pushing `/library`. The existing settings icon stays.

### Route

```
/setup   → SetupScreen
/library → LocalLibraryScreen
```

`LocalLibraryScreen` reads the library folder URI from `settingsProvider` — no route parameters needed.

---

## Section 2: Data Layer

### New dependency

Add `archive` to `pubspec.yaml` (pure Dart, no native code) for ZIP decompression and recompression of `.fb2.zip` files.

### Domain model

```dart
// lib/domain/entities.dart (or a new lib/domain/local_library.dart)
class LocalBookMetadata {
  final String title;
  final String author;    // full name; comma-separated for multiple authors
  final String? series;
  final int? seriesIndex;
}
```

### FB2 metadata parsing — `Fb2MetadataParser`

Location: `lib/data/fb2_metadata_parser.dart`

Parses the XML `<title-info>` block:

- `<book-title>` → `title`
- All `<author>` elements: for each, join `<first-name>`, `<middle-name>`, `<last-name>` with single spaces (trim each part, drop empty parts). Join all resulting author strings with `", "` → `author`
- `<sequence name="..." number="..."/>` → `series` (name attribute) and `seriesIndex` (number attribute parsed as `int?`)

For `.fb2.zip`: use `archive` to decompress, extract the first `.fb2` entry, then parse as above.

### FB2 metadata writing — `Fb2MetadataWriter`

Location: `lib/data/fb2_metadata_writer.dart`

Patches an in-memory XML document (parsed by the `xml` package):

- **Author**: replace all `<author>` elements in `<title-info>` with a single `<author><last-name>full string</last-name></author>`. If the author string contains a comma (`"Tolkien, Lewis"`), the entire string goes into `<last-name>` as-is.
- **Series**: if `series` is non-null, upsert `<sequence name="..." number="..."/>` in `<title-info>`; if `series` is null, remove the `<sequence>` element.
- **seriesIndex**: written as the `number` attribute on `<sequence>`; omitted if null.
- All other XML content (body, cover image, etc.) is left untouched.

For `.fb2.zip`: decompress → patch XML → recompress → return patched bytes.

### SQLite cache — `SqfliteLocalLibraryCache`

Location: `lib/data/sqflite_local_library_cache.dart`

New table added to the existing `AppDatabase` migration:

```sql
CREATE TABLE local_book_cache (
  path       TEXT PRIMARY KEY,   -- relative path from library root, e.g. "Jane Doe/Series/book.fb2"
  title      TEXT NOT NULL,
  author     TEXT NOT NULL,
  series     TEXT,
  series_index INTEGER
);
```

API:

```dart
Future<LocalBookMetadata?> get(String relativePath);
Future<void> put(String relativePath, LocalBookMetadata meta);
Future<void> putAll(Map<String, LocalBookMetadata> entries);
Future<void> deleteAll();
```

Cache is eternal — entries are only evicted by an explicit `deleteAll()` (triggered by Refresh).

### SAF directory listing — `SafLocalLibraryScanner`

Location: `lib/data/saf_local_library_scanner.dart`

Uses `saf_util` to recursively list a SAF tree. Emits `LibraryFile` records:

```dart
class LibraryFile {
  final String relativePath; // e.g. "Jane Doe/Series/book.fb2"
  final String documentUri;  // SAF document URI for reading/writing
}
```

Only `.fb2` and `.fb2.zip` files are emitted (case-insensitive). Directories are traversed but not emitted.

---

## Section 3: Library Screen — Scan and Tree View

### State machine

`LocalLibraryNotifier extends Notifier<LocalLibraryState>`:

```dart
sealed class LocalLibraryState {}
class LibraryScanning extends LocalLibraryState { final int scanned; final int? total; }
class LibraryReady   extends LocalLibraryState { final LibraryFolder root; final bool validationRun; }
class LibraryError   extends LocalLibraryState { final String message; }
```

### In-memory tree nodes

```dart
sealed class LibraryNode {}

class LibraryFolder extends LibraryNode {
  final String name;
  final List<LibraryNode> children;
  final bool hasWarning;   // true if any descendant book is invalid
}

class LibraryBook extends LibraryNode {
  final String relativePath;
  final String documentUri;
  final LocalBookMetadata meta;
  final bool isInvalid;    // set by Validate; false until first Validate run
}
```

### Scan sequence (on screen enter)

1. `SafLocalLibraryScanner` lists all `.fb2`/`.fb2.zip` files recursively, emitting `LibraryFile` records
2. For each file: cache hit → use `LocalBookMetadata` from SQLite; cache miss → parse via `Fb2MetadataParser` and store in cache
3. Build the `LibraryFolder` tree from relative paths
4. Emit `LibraryReady(root, validationRun: false)`

State transitions through `LibraryScanning` while step 1–3 execute (update `scanned` count as files are processed).

### Refresh

Calls `SqfliteLocalLibraryCache.deleteAll()` then re-runs the scan from scratch.

### Book tile

Mirrors `_BookEntryTile` from `browse_screen.dart`:

- Leading: `Icons.book` (no network cover for local files)
- Title: `meta.title` (2 lines max)
- Subtitle line 1: `meta.author`
- Subtitle line 2: `meta.series` + ` #N` if `seriesIndex` non-null
- Trailing: yellow `Icons.warning_amber_rounded` when `isInvalid && validationRun`; tapping the tile opens the edit bottom sheet

### Folder tile

- Leading: collapse/expand chevron icon
- Title: folder name
- Subtitle: `N book(s)` (total descendant count)
- Trailing: yellow `Icons.warning_amber_rounded` if `hasWarning && validationRun`

### AppBar actions

Left to right: **Refresh** · **Validate** · **Fix**

- All three are disabled while `LibraryScanning`
- Fix is disabled when `!validationRun`

---

## Section 4: Edit Metadata Dialog

Tapping a book tile opens a modal bottom sheet (`showModalBottomSheet`) with a form:

| Field | Type | Notes |
|---|---|---|
| Title | `TextFormField` | required |
| Author | `TextFormField` | required; comma-separated for multiple |
| Series | `TextFormField` | optional; clearing removes `<sequence>` |
| Series # | `TextFormField` (integer) | optional; disabled when Series is empty |

### Save flow

1. Read file bytes via `saf_stream` using `documentUri`
2. `Fb2MetadataWriter` patches the XML in memory
3. Write patched bytes back via `saf_stream.writeFileBytes` (overwrites in-place)
4. `SqfliteLocalLibraryCache.put(relativePath, newMeta)` updates the cache
5. Update the `LibraryBook` node in the in-memory tree and emit a new `LibraryReady` state
6. If `validationRun` is true, re-evaluate this book's validity and propagate `hasWarning` up the folder tree

### Error handling

If the write fails, show a `SnackBar` with the error message. Leave cache and in-memory tree unchanged.

Cover image bytes inside the FB2 are not touched.

---

## Section 5: Validate and Fix

### Validate

Pure in-memory pass — no file I/O. Runs over the `LibraryReady` tree.

**Validity check per book** (from `relativePath`):

Let `segments` = path split by `/` with the filename removed.  
`depth` = `segments.length`  (0 = file in root, 1 = one folder, 2 = two folders, etc.)

| depth | condition for VALID |
|---|---|
| 0 | never valid |
| 1 | `meta.series == null` AND `segments[0]` == `meta.author` (case-insensitive, trimmed) |
| 2 | `meta.series != null` AND `segments[0]` == `meta.author` AND `segments[1]` == `meta.series` (case-insensitive, trimmed) |
| > 2 | never valid |

After evaluating all books, `hasWarning` is propagated bottom-up: a folder is `hasWarning` if any descendant book is invalid.

Emits a new `LibraryReady(root: annotatedRoot, validationRun: true)`.

### Fix

Iterates all `LibraryBook` nodes where `isInvalid == true`.

| depth | action |
|---|---|
| 0 | skip |
| 1 | `author = segments[0]`, clear `series` and `seriesIndex` |
| 2 | `author = segments[0]`, `series = segments[1]`, preserve existing `seriesIndex` |
| > 2 | skip |

For each fixed book:
1. Parse current file bytes and patch via `Fb2MetadataWriter`
2. Write back via SAF
3. Update SQLite cache
4. Update `LibraryBook` node in-memory

After all fixes, Validate re-runs automatically to clear/update warning icons.

A `SnackBar` reports `"Fixed N books, skipped M"`.

---

## Section 6: Testing

### `Fb2MetadataParser` — `test/data/fb2_metadata_parser_test.dart`

- Single author (first + middle + last → joined)
- Multiple `<author>` elements → comma-separated
- Missing fields (no series, no series number)
- Malformed XML → throws a typed exception
- `.fb2.zip` fixture: minimal zip containing a valid fb2

### `Fb2MetadataWriter` — `test/data/fb2_metadata_writer_test.dart`

- Round-trip: parse → modify title/author/series → write → re-parse → assert new values
- Verify untouched nodes (body, cover image bytes) are preserved
- Clearing series removes `<sequence>`
- Multiple authors stored as single `<last-name>` string

### `SqfliteLocalLibraryCache` — `test/data/sqflite_local_library_cache_test.dart`

- `get` returns null on miss
- `put` then `get` returns the stored metadata
- `put` overwrites an existing entry
- `putAll` stores multiple entries atomically
- `deleteAll` leaves the table empty

### Validation logic — `test/domain/local_library_validator_test.dart`

Pure-function tests (no I/O). A `LocalLibraryValidator.validate(LibraryFolder)` static/top-level function returns an annotated tree.

- depth 0 → invalid
- depth 1, no series, name matches → valid
- depth 1, no series, name mismatch → invalid
- depth 1, has series → invalid (series but wrong depth)
- depth 2, has series, both names match → valid
- depth 2, has series, author mismatch → invalid
- depth 2, has series, series mismatch → invalid
- depth 2, no series → invalid
- depth 3 → invalid
- Case-insensitive and trim handling
- Folder `hasWarning` propagation

### Fix logic — `test/domain/local_library_fixer_test.dart`

Small in-memory tree, fake writer:

- depth 1: author written, series cleared
- depth 2: author and series written, seriesIndex preserved
- depth 0 and depth 3: skipped (writer not called)

### `LocalLibraryNotifier` — `test/ui/local_library_notifier_test.dart`

Fake `SafLocalLibraryScanner` and fake cache:

- Scan transitions: `LibraryScanning` → `LibraryReady`
- Cache hit avoids parser call
- Refresh calls `deleteAll` then rescans
- Validate sets `isInvalid` flags and `validationRun: true`
- Fix calls writer for invalid books only, then re-validates

---

## File Map

```
lib/
  domain/
    local_library.dart           # LocalBookMetadata, LibraryNode tree types,
                                 # LocalLibraryValidator, LocalLibraryFixer (pure logic)
  data/
    fb2_metadata_parser.dart
    fb2_metadata_writer.dart
    saf_local_library_scanner.dart
    sqflite_local_library_cache.dart
  ui/
    setup_screen.dart
    local_library_screen.dart    # LocalLibraryNotifier + screen widgets
    widgets/
      edit_book_metadata_sheet.dart
test/
  domain/
    local_library_validator_test.dart
    local_library_fixer_test.dart
  data/
    fb2_metadata_parser_test.dart
    fb2_metadata_writer_test.dart
    sqflite_local_library_cache_test.dart
  ui/
    local_library_notifier_test.dart
  fixtures/
    minimal.fb2
    minimal.fb2.zip
```

# OPDS Catalogue Browser — Functional & Technical Specification

**Version:** 1.0 (2026-06-11)
**Status:** Approved for implementation
**Audience:** This document is written to be handed to an implementation agent/model. Where a decision is already made, it is stated as a hard requirement ("MUST"). Do not re-litigate decided items; if something is genuinely ambiguous, see §15 Open Questions.

---

## 1. Overview

An Android-only mobile application (built with Flutter) for browsing open, free OPDS catalogues and downloading books from them. No accounts, no login, no billing, no DRM. Books are **not** read inside the app — downloaded books are opened with an external reader app chosen by the OS.

### 1.1 Core use cases

1. Register one or more OPDS catalogues by URL; edit and delete them.
2. Browse a catalogue's folder hierarchy (navigation feeds), with instant "back" thanks to a persistent cache.
3. Download a single book (preferring FB2 format) or an entire folder recursively.
4. Bookmark ("favorite") any catalogue folder for one-tap access from the start screen.
5. Configure the download location and folder-naming options.

### 1.2 Non-goals (explicitly out of scope for v1)

- OPDS 2.0 support (but the architecture MUST allow adding it later — see §4).
- Catalog search / OpenSearch.
- Authentication of any kind (HTTP Basic, OAuth, etc.). Catalogs requiring auth fail with a clear error.
- In-app reading, reading progress, library management of downloaded files.
- iOS support. Do not add iOS-specific code or conditional platform branches beyond what Flutter generates.
- Tablet-specific layouts. A single phone-oriented responsive layout is sufficient.

---

## 2. Tech stack (decided — do not substitute)

| Concern | Choice |
|---|---|
| Framework | Flutter (latest stable), Dart, null-safety |
| State management | Riverpod (`flutter_riverpod`), plain `Notifier`/`AsyncNotifier` classes; no code-gen variant required |
| Navigation | `go_router` |
| HTTP | `http` package (keep it simple; no dio) |
| XML parsing | `xml` package |
| Local DB | `sqflite` (schema in §6; raw SQL is acceptable, keep DAOs thin) |
| Key-value settings | `shared_preferences` |
| Cover images | `cached_network_image` |
| Open downloaded file externally | `open_filex` |
| Default downloads (MediaStore) & custom folder (SAF) | `shared_storage` (or equivalent maintained SAF/MediaStore plugin; requirement is behavioral, see §10) |
| Timestamps "X ago" | implement a small pure Dart helper, unit-tested; do not pull a heavy i18n lib |
| Lints | `flutter_lints` + strict `analysis_options.yaml` (`strict-casts`, `strict-raw-types`, `strict-inference` enabled) |

**Conventions:**

- All business logic MUST live in plain Dart classes that are testable without Flutter bindings.
- Every public class in `lib/domain` and `lib/data` MUST have unit tests (see §13).
- Single package, no monorepo. Suggested layout:

```
lib/
  domain/        # entities, value objects, repository interfaces, the OpdsClient interface
  data/          # OPDS 1.x implementation, DB, settings store, download engine
  ui/            # screens, widgets, Riverpod providers
  app.dart       # router + theme
  main.dart
test/
  fixtures/      # .xml feed fixtures committed to the repo
  domain/ data/ ui/
```

---

## 3. Domain glossary

- **Catalog** — a root OPDS source registered by the user (title + root URL).
- **Feed** — the content of one catalogue URL: a list of entries. Corresponds to one "folder" as seen by the user.
- **Navigation entry** — an entry that links to another feed (a sub-folder).
- **Book entry (acquisition entry)** — an entry with one or more acquisition links (downloadable formats).
- **Favorite** — a saved pointer to a specific feed URL inside a specific catalog, shown on the start screen.

A single feed MAY contain both navigation entries and book entries; the UI must handle mixed feeds.

---

## 4. Architecture: protocol abstraction layer

OPDS 1.x (Atom/XML) is implemented in v1. OPDS 2.0 (JSON) must be addable later **without changing domain logic, caching, downloads, or UI**. Therefore:

### 4.1 The `OpdsClient` interface (domain layer)

```dart
/// Protocol-agnostic catalogue access. One implementation per protocol version.
abstract interface class OpdsClient {
  /// Fetches and parses the feed at [url]. Never reads or writes cache.
  /// Throws [OpdsException] subtypes on network / parse errors.
  Future<ParsedFeed> fetchFeed(Uri url);

  /// Returns true if this client can handle the document at [url]
  /// (used for protocol auto-detection when adding a catalog).
  Future<bool> probe(Uri url);
}
```

### 4.2 Protocol-neutral parsed model

All downstream code (cache, UI, downloads) depends ONLY on these types:

```dart
class ParsedFeed {
  final String title;
  final List<FeedEntry> entries;
  final Uri? nextPageUrl;       // OPDS pagination, rel="next"; null if last page
}

sealed class FeedEntry {}

class NavigationEntry extends FeedEntry {
  final String title;
  final String? subtitle;       // Atom content/summary, plain text
  final Uri url;                // resolved absolute URL of the sub-feed
}

class BookEntry extends FeedEntry {
  final String title;
  final List<String> authors;   // display order preserved
  final String? series;         // null if absent
  final double? seriesIndex;    // may be fractional (e.g. 1.5); null if absent
  final String? summary;        // plain text, HTML stripped
  final Uri? coverUrl;          // thumbnail preferred over full image
  final List<AcquisitionLink> acquisitionLinks; // non-empty
}

class AcquisitionLink {
  final Uri url;                // resolved absolute
  final String mimeType;        // as declared in the feed
  final String formatLabel;     // human label derived from mimeType, e.g. "FB2", "EPUB", "PDF"
}
```

`ParsedFeed` and all entry types MUST be JSON-serializable (`toJson`/`fromJson`) because the cache stores them as JSON (§7).

### 4.3 OPDS 1.x implementation requirements (`Opds1Client`)

- Parse Atom feeds per the OPDS 1.1/1.2 spec. Be lenient: real-world catalogues are sloppy.
- **Entry classification:** an entry is a `BookEntry` if it has at least one link whose `rel` starts with `http://opds-spec.org/acquisition`; otherwise, if it has a link with type `application/atom+xml` (any profile) it is a `NavigationEntry`; entries with neither are dropped silently.
- **URL resolution:** all link `href`s are resolved against the feed's own URL (respect `xml:base` if present).
- **Authors:** all `<author><name>` values, in document order.
- **Series:** read Calibre-style `<meta name="calibre:series">` / `calibre:series_index` AND the EPUB-ish `<dcterms:isPartOf>` patterns if present; first match wins. If neither, series is null. (Implementor: also accept the common `opds:series` / `schema:Series` link/element variants found in OPDS catalogs; keep this logic in one function `extractSeries(XmlElement entry)` with thorough unit tests.)
- **Cover:** prefer link rel `http://opds-spec.org/image/thumbnail`, fall back to `http://opds-spec.org/image`; null if neither.
- **Pagination:** `rel="next"` link of the feed → `nextPageUrl`.
- **Acquisition mime → label** mapping (one pure function):
  - `application/fb2`, `application/x-fictionbook+xml` → `FB2`
  - `application/fb2+zip`, `application/x-zip-compressed-fb2` → `FB2.ZIP`
  - `application/epub+zip` → `EPUB`
  - `application/pdf` → `PDF`
  - `application/x-mobipocket-ebook` → `MOBI`
  - anything else → uppercase subtype, e.g. `application/djvu` → `DJVU`
- Encoding: handle non-UTF-8 declared encodings (many Russian-language catalogues use windows-1251).
- Network: 20 s timeout per request; send header `User-Agent: OpdsBrowser/1.0`; follow up to 5 redirects.

### 4.4 Error taxonomy

```dart
sealed class OpdsException implements Exception { final String message; }
class NetworkException extends OpdsException {}      // DNS, timeout, no connection
class HttpStatusException extends OpdsException {}   // non-2xx; carries statusCode
class ParseException extends OpdsException {}        // malformed XML / not a feed
class UnsupportedProtocolException extends OpdsException {} // probe failed
```

UI maps these to user-facing messages (§12).

---

## 5. Repositories (domain interfaces, data implementations)

```dart
abstract interface class CatalogRepository {
  Future<List<Catalog>> getAll();
  Future<Catalog> add(String title, Uri rootUrl);     // assigns id
  Future<void> update(Catalog catalog);
  Future<void> delete(int catalogId);                 // cascades: cache, favorites
}

abstract interface class FeedRepository {
  /// Cache-first. Returns cached feed if present (any age), else fetches,
  /// caches, and returns. [forceRefresh] bypasses and overwrites cache.
  Future<CachedFeed> getFeed(int catalogId, Uri url, {bool forceRefresh = false});
}

class CachedFeed {
  final ParsedFeed feed;          // with all pages merged, see §7.3
  final DateTime fetchedAt;       // when this cache entry was written
  final bool fromCache;
}

abstract interface class FavoritesRepository {
  Future<List<Favorite>> getAll();                    // ordered by sortOrder
  Future<void> add(int catalogId, Uri url, String title);
  Future<void> remove(int favoriteId);
  Future<bool> isFavorite(int catalogId, Uri url);
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class AppSettings {
  final DownloadTarget target;        // systemDownloads | customSafFolder(uriString)
  final bool createAuthorFolder;      // default false
  final bool createSeriesFolder;      // default false
}
```

Entities:

```dart
class Catalog { final int id; final String title; final Uri rootUrl; final String protocol; /* "opds1" */ }
class Favorite { final int id; final int catalogId; final Uri url; final String title; final int sortOrder; }
```

---

## 6. Persistence schema (sqflite, single DB `opds_browser.db`, version 1)

```sql
CREATE TABLE catalogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  root_url TEXT NOT NULL,
  protocol TEXT NOT NULL DEFAULT 'opds1',
  created_at INTEGER NOT NULL            -- epoch millis
);

CREATE TABLE feed_cache (
  catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
  url TEXT NOT NULL,                     -- normalized absolute URL (see §7.2)
  feed_json TEXT NOT NULL,               -- ParsedFeed.toJson(), all pages merged
  fetched_at INTEGER NOT NULL,           -- epoch millis
  PRIMARY KEY (catalog_id, url)
);

CREATE TABLE favorites (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  UNIQUE (catalog_id, url)
);
```

`PRAGMA foreign_keys = ON` must be set on every connection. Settings live in `shared_preferences` (keys: `download_target_kind`, `download_target_uri`, `folder_per_author`, `folder_per_series`).

---

## 7. Feed caching (core requirement)

### 7.1 Policy

- **Cache forever.** A cached feed never expires automatically.
- On opening a folder: if a cache row exists → render it **immediately** (no spinner), regardless of age. If none exists → show loading state, fetch, cache, render.
- The browse screen header always shows **"Updated: \<relative time\>"** (e.g. "Updated: 3 days ago", "Updated: just now") derived from `fetched_at`, plus a **refresh button**. Pull-to-refresh does the same as the button.
- Manual refresh: fetch fresh, overwrite cache row, update UI. While refreshing, keep showing the cached content with a thin progress indicator; on failure keep cached content and show a snackbar error.
- "Back" navigation MUST NOT trigger any network call — it re-reads the cache (or an in-memory layer above it).

### 7.2 Cache key normalization

Key = `(catalog_id, normalizeUrl(url))`. `normalizeUrl`: lowercase scheme and host, remove default ports, keep path/query as-is, strip fragments. Pure function, unit-tested.

### 7.3 Pagination and the cache

When fetching a feed (initial or refresh), the fetcher MUST follow `rel="next"` links and merge all pages into one `ParsedFeed` before caching, with a hard safety cap of **50 pages or 5000 entries**, whichever comes first (then stop and cache what was collected). Rationale: the user's mental model is "a folder", and the recursive folder download (§11) needs complete listings. Show "Loading page N…" progress while a multi-page fetch runs.

---

## 8. Screens & navigation

`go_router` routes:

```
/                          StartScreen (catalog list + favorites)
/browse?catalogId&url      BrowseScreen (one instance per folder; stack = folder depth)
/settings                  SettingsScreen
```

### 8.1 StartScreen

Two sections in one scrollable view:

1. **Favorites** (shown only if non-empty): list of favorite folders; each row shows favorite title + parent catalog title; tap → BrowseScreen for that URL; long-press or trailing menu → "Remove from favorites".
2. **Catalogs**: list of registered catalogs; each row: title + root URL (secondary line); tap → BrowseScreen at root URL; trailing overflow menu → Edit / Delete.

App bar: title "OPDS Browser", actions: Settings icon. Floating action button: **"Add catalog"**.

**Add/Edit catalog dialog (or full-screen form):** fields *Title* (required, non-empty) and *URL* (required). On save of a new catalog: prepend `https://` if no scheme given, run `Opds1Client.probe(url)`; on success save; on failure show inline error "Not a supported OPDS catalogue" with the option **"Save anyway"**. Edit pre-fills fields; changing the URL keeps the catalog id (cache rows simply become unreachable; acceptable).

**Delete catalog:** confirmation dialog warning that its favorites and cache will be removed; delete cascades per schema.

**Empty state** (no catalogs): a friendly hint and the Add button.

### 8.2 BrowseScreen

- App bar: feed title; subtitle line "Updated: X ago"; actions: **Refresh**, **Favorite toggle** (star icon, filled when this URL is a favorite), **Download folder** (icon only enabled after feed loaded).
- Body: single list, navigation entries and book entries interleaved exactly in feed order.
  - **Navigation entry row:** folder icon, title, optional subtitle (1 line, ellipsized). Tap → push BrowseScreen for its URL.
  - **Book entry row:** cover thumbnail (placeholder if none, fixed size ~56×80), title (max 2 lines), authors line, series line "Series name #index" if present. Tap → **Book details bottom sheet**.
- **Book details bottom sheet:** cover, title, authors, series, scrollable summary, then a **Download** button plus the list of available formats. Download behavior per §9.
- States: loading (only when no cache), error (message + Retry button; if stale cache exists show it with an error snackbar instead of a full-screen error), empty feed ("This folder is empty").

### 8.3 SettingsScreen

- **Downloads folder** group:
  - Radio "System Downloads folder" (default).
  - Radio "Custom folder…" → tapping launches the SAF directory picker (§10.2); on success show the chosen folder's display name under the radio; on cancel revert selection.
- **File organization** group:
  - Checkbox "Create a folder per author" (default off).
  - Checkbox "Create a folder per series" (default off).
  - Caption explaining the resulting path, live-updated example, e.g. `Downloads/Jane Doe/Great Series/Jane Doe - Great Series #1 - Book Title.fb2`.
- Settings persist immediately on change.

---

## 9. Single book download

### 9.1 Format selection ("prefer FB2, picker otherwise")

Given `acquisitionLinks`:

1. If exactly one link → download it directly on Download tap.
2. If multiple links and one of them is FB2 (labels `FB2` or `FB2.ZIP`; prefer `FB2` over `FB2.ZIP` if both) → the Download button downloads that one directly; the other formats remain listed in the sheet as secondary tap-to-download rows.
3. If multiple links and none is FB2 → the Download button opens a format picker (simple dialog listing `formatLabel`s); the secondary rows behave the same.

Implement choice logic as a pure function `AcquisitionLink? preferredLink(List<AcquisitionLink>)` (returns null when a picker is required) — unit-tested.

### 9.2 File naming

```
<Authors> - [<Series> #<Index> - ]<Title>.<ext>
```

- Authors: first author only if more than 2, suffixed "et al." (e.g. `Jane Doe et al.`); two authors joined with ", ".
- Series segment included only when series is non-null; index formatted without trailing `.0` (1.0 → `1`, 1.5 → `1.5`); omit `#<Index>` when seriesIndex is null.
- Extension from format label: `FB2`→`fb2`, `FB2.ZIP`→`fb2.zip`, `EPUB`→`epub`, `PDF`→`pdf`, `MOBI`→`mobi`, else lowercase label.
- Sanitization: replace characters `\ / : * ? " < > |` and control chars with `_`; collapse whitespace; trim; cap full filename at 200 chars (truncate title part).
- Pure function `buildFileName(BookEntry, AcquisitionLink)` — unit-tested heavily.

### 9.3 Destination path

```
<root>/[<AuthorFolder>/][<SeriesFolder>/]<filename>
```

- `<root>` per settings (§10). AuthorFolder = same author string as in the filename; SeriesFolder = series name; both sanitized with the same function. Each segment is created only if the corresponding checkbox is on AND the data exists (no "Unknown author" folders — if data missing, skip that level).
- If a file with the same name already exists at the destination: skip the download and report "Already downloaded" (no overwrite, no duplicate numbering) — this also makes folder downloads resumable.

### 9.4 UX

- Download runs in background (Dart isolate not required; async is fine), with a progress indicator in the bottom sheet and a snackbar on completion: "Downloaded <filename>" with an **Open** action → `open_filex` on the saved file. If no app can open it, show "No reader app installed for this format".
- Errors: snackbar with reason and a Retry action.

---

## 10. Storage backends (Android specifics)

### 10.1 Default: system Downloads

Use MediaStore `Downloads` collection (API 29+; `minSdkVersion 29` is acceptable and RECOMMENDED to avoid legacy storage permissions entirely). Subfolders (author/series) are expressed via the MediaStore relative path (`Environment.DIRECTORY_DOWNLOADS + "/Author/Series"`). No runtime permission dialogs needed.

### 10.2 Custom folder: Storage Access Framework

- "Custom folder…" triggers `ACTION_OPEN_DOCUMENT_TREE`; on result, call `takePersistableUriPermission` (read+write) and store the tree URI string in settings. This IS the "OS permissions request" from the requirements.
- Writing: create sub-directories and files via SAF (`DocumentFile`-equivalent through the chosen plugin). Existence check by listing/finding the child by display name.
- On app start, verify the persisted permission still holds; if revoked/missing, fall back to system Downloads and show a one-time notice "Custom downloads folder is no longer accessible — reverted to system Downloads."

### 10.3 Abstraction

```dart
abstract interface class DownloadStorage {
  /// Returns true if a file with this relative path already exists.
  Future<bool> exists(List<String> pathSegments, String fileName);
  /// Streams [bytes] into the file, creating intermediate folders. Returns
  /// an opaque locator usable by open_filex (file path or content URI).
  Future<String> write(List<String> pathSegments, String fileName, Stream<List<int>> bytes);
}
```

Two implementations: `MediaStoreDownloadStorage`, `SafDownloadStorage`. Domain/download code depends only on the interface (this also makes the download engine unit-testable with an in-memory fake).

---

## 11. Folder ("download everything") download

Triggered by the Download-folder action on BrowseScreen, with a confirmation dialog: "Download all books in this folder and its subfolders? This may be a large amount of data."

Algorithm (class `FolderDownloadJob`, pure-logic core unit-tested with fakes):

1. BFS traversal starting at the current feed URL. Use `FeedRepository.getFeed` (cache-first — already-cached subfolders cost zero network).
2. Safety limits: max depth 10, max 500 folders, max 2000 books per job; on hitting a limit, finish what was collected and report "Stopped at safety limit".
3. Cycle protection: keep a set of normalized visited URLs.
4. For every `BookEntry`: choose format via `preferredLink`; when a picker would be required (no FB2 among several), apply order of preference `FB2 > FB2.ZIP > EPUB > PDF > MOBI > first listed` instead of asking.
5. Download queue with concurrency 2. Skip files that already exist (§9.3).
6. Progress UI: a persistent bottom banner (or simple dialog) on the BrowseScreen showing "Scanning folders… (N found)" then "Downloading X of Y", a Cancel button (cancels pending, lets in-flight finish), and a final summary: downloaded / skipped (already existed) / failed counts.
7. Individual file failures don't abort the job; they increment the failed counter. The job survives screen rotation but MAY be cancelled if the user leaves the app (no foreground service in v1 — document this limitation in code comments).

---

## 12. Error message mapping

| Exception | User message |
|---|---|
| NetworkException | "Network error. Check your connection and try again." |
| HttpStatusException 404 | "This folder no longer exists on the server." |
| HttpStatusException 401/403 | "This catalogue requires authentication, which is not supported." |
| HttpStatusException other | "Server error (HTTP \<code\>)." |
| ParseException | "The server response is not a valid OPDS feed." |
| UnsupportedProtocolException | "Not a supported OPDS catalogue." |

---

## 13. Testing strategy (TDD — mandatory)

Development MUST be test-first wherever practical. All tests run with `flutter test` on the host; no emulator, no device, no integration_test package in v1.

1. **Fixtures:** commit real-world-ish OPDS 1.x XML samples under `test/fixtures/`: minimal navigation feed; mixed feed (folders + books); book with multiple formats incl. FB2; book without FB2; entries with series metadata (Calibre style and link style); paginated feed (2+ pages); windows-1251 encoded feed; malformed XML; empty feed; feed with relative hrefs + `xml:base`.
2. **Unit tests (pure Dart):** `Opds1Client` parsing against every fixture (HTTP mocked with `http`'s `MockClient`); `normalizeUrl`; `extractSeries`; mime→label mapping; `preferredLink`; `buildFileName` (incl. sanitization edge cases); relative-time formatter; `FolderDownloadJob` traversal with a fake `FeedRepository` and fake `DownloadStorage` (verifies cycle protection, limits, skip-existing, failure counting).
3. **Repository tests:** sqflite via `sqflite_common_ffi` (runs on host): CRUD, cascade deletes, cache overwrite on refresh, favorites uniqueness.
4. **Widget tests:** StartScreen (empty state, list rendering, add-dialog validation); BrowseScreen (renders cached feed instantly, shows "Updated X ago", refresh keeps content on failure, mixed entry rendering); book bottom sheet (FB2 direct download vs picker); SettingsScreen (path example caption updates with checkboxes). Use Riverpod provider overrides with fakes — never real network or DB in widget tests.
5. **Quality gate:** `flutter analyze` clean and `flutter test` green are required before any task is considered complete. Provide a `Makefile` with `make check` running both.

---

## 14. Suggested implementation order

1. Project scaffold, lints, Makefile, CI-style `make check`.
2. Domain models + `OpdsClient` interface + fixtures.
3. `Opds1Client` (TDD against fixtures).
4. DB layer + repositories (TDD with sqflite_common_ffi).
5. `FeedRepository` with caching + pagination merge.
6. StartScreen + catalog CRUD + navigation shell.
7. BrowseScreen (cache-first rendering, refresh, favorites toggle).
8. Settings + `DownloadStorage` implementations.
9. Single-book download + bottom sheet.
10. Folder download job.
11. Polish: error mapping, empty states, app icon.

---

## 15. Open questions (do not block; defaults below apply unless the owner says otherwise)

1. Cache size management: no eviction in v1 (cache forever). If a "Clear cache" affordance is desired, the natural place is SettingsScreen.
2. App display name and icon: placeholder "OPDS Browser" until decided.

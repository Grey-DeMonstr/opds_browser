# Folder Download — Tree Selection Redesign

**Date:** 2026-06-27
**Status:** Approved
**Supersedes:** `2026-06-14-folder-download-design.md`

---

## Overview

Replace the current "scan-then-immediately-download-everything" folder download with a two-stage
flow: (1) scan the full folder tree into a visual tree screen where the user selects which books
to download, then (2) download only the selected books sequentially with a 5-second pause between
each, with live per-book progress shown on the same screen.

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | Extend existing `FolderDownloadJob` | BFS logic, cycle protection, and limits are correct and well-tested |
| Scan UX | Full-screen `FolderScanScreen` with live progress | Simple; no partial tree state complexity |
| Tree UX | `FolderTreeScreen` — full lifecycle (select → download → done) | One screen owns the full flow |
| Format selection | Auto-select via `folderPreferredLink()` | No per-book picker in tree; keeps UI clean |
| Download concurrency | Sequential (one at a time) | 5-second inter-book delay is global; concurrency would require per-worker delays |
| Inter-book delay | 5 seconds (hardcoded) | Avoid server-side rate limiting |
| Safety limits | Keep (depth ≤ 10, ≤ 500 folders, ≤ 2000 books) | Protects against huge catalogues; user still sees what was found |
| `FolderJobBanner` | Deleted | Tree screen owns all download state display |
| Error display | `AlertDialog` on tap of red warning icon | Android touch-only; no hover |
| Done state | "Close" button pops tree screen | User reviews results then explicitly returns |

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/domain/models.dart` | Modify | Add `DownloadTreeNode`, `DownloadBook`, `DownloadFolder`, `BookDownloadResult`, `BookDownloadStatus` |
| `lib/data/folder_download_job.dart` | Rewrite | Scan builds tree; new `FolderJobTreeReady` state; sequential download with 5s pause; per-book result tracking |
| `lib/ui/providers.dart` | Modify | Add `FolderJobTreeReady` to state union; add `confirmDownload(Set<Uri>)` to notifier; remove `dismiss()` |
| `lib/ui/folder_scan_screen.dart` | Create | Shows scan progress; auto-navigates to tree when ready |
| `lib/ui/folder_tree_screen.dart` | Create | Tree selection → download progress → done, all in one screen |
| `lib/ui/browse_screen.dart` | Modify | Remove `FolderJobBanner` embed; update AppBar button guard; navigate to scan screen |
| `lib/ui/widgets/folder_job_banner.dart` | Delete | Replaced by in-screen progress |
| `test/data/folder_download_job_test.dart` | Rewrite | Tree building, single-book collapse, sequential download, per-book results, 5s delay, cancellation |
| `test/ui/folder_download_notifier_test.dart` | Rewrite | New state transitions including `FolderJobTreeReady` and `confirmDownload` |
| `test/ui/browse_screen_test.dart` | Modify | Remove banner tests; update button guard logic |
| `test/ui/folder_scan_screen_test.dart` | Create | Progress display and auto-navigation |
| `test/ui/folder_tree_screen_test.dart` | Create | Checkbox logic, tri-state, mode transitions, error popup |

---

## 1. Domain model additions (`lib/domain/models.dart`)

### 1.1 Download tree nodes

```dart
sealed class DownloadTreeNode { const DownloadTreeNode(); }

class DownloadBook extends DownloadTreeNode {
  const DownloadBook({
    required this.entry,
    required this.link,
    this.inferredSeries,
  });
  final BookEntry entry;
  final AcquisitionLink link;       // pre-selected via folderPreferredLink()
  final String? inferredSeries;
}

class DownloadFolder extends DownloadTreeNode {
  const DownloadFolder({required this.title, required this.children});
  final String title;
  final List<DownloadTreeNode> children;
}
```

### 1.2 Per-book download result

```dart
enum BookDownloadStatus { downloading, done, skipped, failed }

class BookDownloadResult {
  const BookDownloadResult({required this.status, this.error});
  final BookDownloadStatus status;
  final String? error;    // non-null when status == failed
}
```

---

## 2. State model (`lib/ui/providers.dart`)

```dart
sealed class FolderJobState { const FolderJobState(); }

class FolderJobIdle extends FolderJobState {
  const FolderJobIdle();
}

class FolderJobScanning extends FolderJobState {
  const FolderJobScanning({required this.foldersFound});
  final int foldersFound;
}

/// Scan complete — user selects which books to download.
class FolderJobTreeReady extends FolderJobState {
  const FolderJobTreeReady({required this.root, required this.checkedBooks});
  final DownloadTreeNode root;
  final Set<Uri> checkedBooks;    // link URLs; all books checked by default
}

/// Download in progress — shows checked-only subtree with per-book status.
class FolderJobDownloading extends FolderJobState {
  const FolderJobDownloading({
    required this.root,
    required this.results,
    required this.total,
    required this.completedCount,
    this.currentBook,
  });
  final DownloadTreeNode root;              // checked-only subtree
  final Uri? currentBook;                   // link URL currently downloading
  final Map<Uri, BookDownloadResult> results;
  final int total;
  final int completedCount;
}

class FolderJobDone extends FolderJobState {
  const FolderJobDone({
    required this.root,
    required this.results,
    required this.wasCancelled,
    required this.stoppedAtLimit,
  });
  final DownloadTreeNode root;
  final Map<Uri, BookDownloadResult> results;
  final bool wasCancelled;
  final bool stoppedAtLimit;
}
```

---

## 3. `FolderDownloadJob` rewrite (`lib/data/folder_download_job.dart`)

Pure Dart — no Flutter or platform dependencies.

### 3.1 Constructor (unchanged shape)

```dart
class FolderDownloadJob {
  FolderDownloadJob({
    required FeedRepository feedRepository,
    required DownloadFn downloadFn,    // renamed from 'download' to avoid clash with download() method
    required AppSettings settings,
    required void Function(FolderJobState) onProgress,
  });

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  Future<void> run(int catalogId, Uri startUrl) async { ... }
  Future<void> download(Set<Uri> checkedBooks) async { ... }
}
```

### 3.2 Phase 1 — BFS scan → tree

BFS traversal identical to current implementation (same limits, cycle protection, feed-error
resilience), except the output is a tree rather than a flat task list.

**Tree construction:** each visited navigation feed becomes a `DownloadFolder`; each `BookEntry`
becomes a `DownloadBook` (with `folderPreferredLink()` applied). The tree is built bottom-up as
feeds are processed.

**Single-book folder collapsing:** after BFS completes, a recursive post-processing pass replaces
any `DownloadFolder` whose children list collapses to exactly one node with that node directly.
The pass is applied repeatedly until stable (handles chains: folder → folder → book → collapses
to book).

```dart
DownloadTreeNode _collapse(DownloadTreeNode node) {
  if (node is DownloadBook) return node;
  final folder = node as DownloadFolder;
  final collapsed = folder.children.map(_collapse).toList();
  if (collapsed.length == 1) return collapsed.first;
  return DownloadFolder(title: folder.title, children: collapsed);
}
```

**Series inference:** `inferSeriesFromUrl(feedUrl)` is applied per feed URL and threaded into
each `DownloadBook.inferredSeries` (same logic as the current BFS implementation).

**On scan complete:**
```dart
final allBookUrls = _collectBookUrls(root);   // DFS collect all link.url values
onProgress(FolderJobTreeReady(root: root, checkedBooks: allBookUrls));
```

If scan was cancelled or produced zero books:
```dart
onProgress(FolderJobDone(root: root, results: {}, wasCancelled: _cancelled, stoppedAtLimit: stoppedAtLimit));
```

### 3.3 Phase 2 — sequential download with 5-second pause

Called via a separate entry point: `Future<void> download(Set<Uri> checkedBooks)`.

```dart
Future<void> download(Set<Uri> checkedBooks) async {
  final tasks = _collectTasks(root, checkedBooks);  // DFS, preserves tree order

  final results = <Uri, BookDownloadResult>{};
  final checkedOnlyRoot = _filterTree(root, checkedBooks);

  for (int i = 0; i < tasks.length; i++) {
    if (_cancelled) break;

    final task = tasks[i];
    onProgress(FolderJobDownloading(
      root: checkedOnlyRoot,
      currentBook: task.link.url,
      results: Map.unmodifiable(results),
      total: tasks.length,
      completedCount: results.length,
    ));

    try {
      final outcome = await download(task.entry, task.link, settings,
          inferredSeries: task.inferredSeries);
      results[task.link.url] = BookDownloadResult(
        status: outcome == 'already_exists'
            ? BookDownloadStatus.skipped
            : BookDownloadStatus.done,
      );
    } catch (e) {
      results[task.link.url] = BookDownloadResult(
        status: BookDownloadStatus.failed,
        error: e.toString(),
      );
    }

    // Pause between books (not after the last one, not if cancelled)
    if (!_cancelled && i < tasks.length - 1) {
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  onProgress(FolderJobDone(
    root: checkedOnlyRoot,
    results: Map.unmodifiable(results),
    wasCancelled: _cancelled,
    stoppedAtLimit: stoppedAtLimit,
  ));
}
```

`_filterTree(root, checkedBooks)` produces a copy of the tree containing only nodes whose subtree
intersects `checkedBooks` — this is the tree shown during download and done states.

---

## 4. `FolderDownloadNotifier` changes (`lib/ui/providers.dart`)

```dart
class FolderDownloadNotifier extends Notifier<FolderJobState> {
  FolderDownloadJob? _job;

  @override
  FolderJobState build() => const FolderJobIdle();

  /// Start the scan phase.
  Future<void> start(int catalogId, Uri url) async {
    if (state is! FolderJobIdle && state is! FolderJobDone) return;
    state = const FolderJobScanning(foldersFound: 0);

    final downloader = ref.read(bookDownloaderProvider);
    if (downloader == null) {
      state = const FolderJobDone(
          root: DownloadFolder(title: '', children: []),
          results: {},
          wasCancelled: true,
          stoppedAtLimit: false);
      return;
    }

    _job = FolderDownloadJob(
      feedRepository: ref.read(feedRepositoryProvider),
      download: downloader.download,
      settings: ref.read(settingsProvider).requireValue,
      onProgress: (s) { state = s; },
    );

    await _job!.run(catalogId, url);
  }

  /// Start the download phase with the user's selection.
  Future<void> confirmDownload(Set<Uri> checkedBooks) async {
    if (state is! FolderJobTreeReady) return;
    await _job!.download(checkedBooks);
    _job = null;
  }

  /// Update checkbox selection while in tree-ready state.
  void updateSelection(Set<Uri> checkedBooks) {
    if (state is FolderJobTreeReady) {
      state = (state as FolderJobTreeReady).copyWith(checkedBooks: checkedBooks);
    }
  }

  /// Reset to idle — called when the user navigates back from the tree screen
  /// without downloading (back button during selection mode).
  void reset() {
    _job?.cancel();
    _job = null;
    state = const FolderJobIdle();
  }

  void cancel() => _job?.cancel();
}

final folderDownloadProvider =
    NotifierProvider<FolderDownloadNotifier, FolderJobState>(
        FolderDownloadNotifier.new);
```

`dismiss()` is removed — the tree screen pops itself on Close.

---

## 5. Navigation

Two new go_router routes, as sub-routes under the browse route. Exact path strings depend on the
existing route structure in `app.dart` — the names below are schematic.

| Route (schematic) | Screen | Pushed when |
|-------------------|--------|-------------|
| `.../folder-scan` | `FolderScanScreen` | User taps folder download button in BrowseScreen |
| `.../folder-tree` | `FolderTreeScreen` | `FolderJobTreeReady` state observed in `FolderScanScreen` |

No dialog confirmation before scanning — the scan screen itself is the entry point. The
cost of accidental tap is low: the user can immediately cancel on the scan screen.

**BrowseScreen** AppBar button:
- Enabled only when state is `FolderJobIdle`
- Navigates to scan screen without confirmation dialog (removed)
- Disabled (not just greyed) while any job is active

---

## 6. `FolderScanScreen` (`lib/ui/folder_scan_screen.dart`)

Full-screen `ConsumerWidget` watching `folderDownloadProvider`.

**On build, starts the job:**
```dart
ref.listen(folderDownloadProvider, (_, next) {
  if (next is FolderJobTreeReady) {
    context.replace('/...folder-tree');
  } else if (next is FolderJobDone) {
    // Cancelled with zero books — pop back
    context.pop();
  }
});
```

**UI:**
- Centered column: `CircularProgressIndicator` + "Scanning… (N folders found)" text
- `stoppedAtLimit` shown as a note if applicable
- "Cancel" `TextButton` at bottom — calls `notifier.cancel()`

---

## 7. `FolderTreeScreen` (`lib/ui/folder_tree_screen.dart`)

`ConsumerStatefulWidget` watching `folderDownloadProvider`.

### 7.1 Checkbox state (selection mode only)

Selection state is derived from `FolderJobTreeReady.checkedBooks`. The widget keeps no local
checkbox state — it calls `notifier.updateSelection(Set<Uri>)` on every toggle, which updates the
`FolderJobTreeReady` state in place.

```dart
// In notifier:
void updateSelection(Set<Uri> checkedBooks) {
  if (state is FolderJobTreeReady) {
    state = (state as FolderJobTreeReady).copyWith(checkedBooks: checkedBooks);
  }
}
```

Tri-state folder logic (derived, not stored):
- All descendant books in `checkedBooks` → checked
- No descendant books in `checkedBooks` → unchecked
- Some → indeterminate

Tapping a folder checkbox:
- If checked or indeterminate → uncheck all descendants
- If unchecked → check all descendants

### 7.2 Tree row rendering

Each `DownloadTreeNode` is rendered as a `ListTile` indented by depth (`padding: EdgeInsets.only(left: depth * 16.0)`).

**Selection mode:**
- `DownloadFolder` row: tri-state `Checkbox` + folder title
- `DownloadBook` row: `Checkbox` + book title (+ author if not in a series context)

**Download / Done mode:**
- Unchecked books (not in `checkedBooks`) are hidden entirely
- Checkboxes replaced by status icons:
  - `currentBook` → `SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))`
  - `done` or `skipped` → `Icon(Icons.check_circle, color: Colors.green)`
  - `failed` → `Icon(Icons.warning_rounded, color: Colors.red)` — tapping shows `AlertDialog` with `error` text; dismissed by tapping outside or the OK button
  - pending (in `checkedBooks` but no result yet and not `currentBook`) → `Icon(Icons.schedule, color: Colors.grey)`

### 7.3 Sticky bottom bar

`Column` layout wrapping the `ListView` in an `Expanded`:

```dart
Column(children: [
  Expanded(child: ListView(...)),  // tree rows
  _BottomBar(),                    // always visible
])
```

**Selection mode:** `FilledButton("Download (N books)", onPressed: checkedBooks.isEmpty ? null : _startDownload)`

**Download mode:** `Row` with `Expanded(child: LinearProgressIndicator(value: completedCount / total))` + `TextButton("Cancel", style: red, onPressed: notifier.cancel)`

**Done mode:** `FilledButton("Close", onPressed: context.pop)` — optionally prefixed by a short notice if `wasCancelled` or `stoppedAtLimit`

**Back-navigation during selection mode:** `FolderTreeScreen` intercepts the system back button
(via `PopScope` / `onPopInvoked`) and calls `notifier.reset()` before popping, so the provider
returns to `FolderJobIdle` and the BrowseScreen button re-enables.

---

## 8. `BrowseScreen` changes

- Remove `FolderJobBanner` from body column
- Update AppBar button guard: enabled only when `state is FolderJobIdle`
- On tap: `context.push('/...folder-scan')` — no confirmation dialog
- Remove `dismiss()` call (no longer exists on notifier)

---

## 9. Testing strategy

### `test/data/folder_download_job_test.dart` (rewrite)

**Scan / tree building:**
- Single feed with one book → `DownloadBook` at root (no wrapping folder after collapse)
- Feed with one nav + one book → folder with one child → collapses to book
- Feed with two nav + three books → `DownloadFolder` with five children (no collapse)
- Nested nav chain leading to one book → collapses recursively
- Cycle protection: same URL visited twice → single node in tree
- `stoppedAtLimit = true` when depth/folder/book limits hit
- Feed error → that folder skipped; rest of tree still built
- `inferredSeries` from URL threaded into `DownloadBook.inferredSeries`

**Download phase:**
- `already_exists` outcome → `BookDownloadStatus.skipped`
- Exception from download fn → `BookDownloadStatus.failed` with `error` populated
- Cancellation mid-download → `wasCancelled: true`, remaining books not started
- 5-second delay called between books (verify with a fake `delay` injectable or `FakeAsync`)
- No delay after the last book
- No delay after cancel
- `FolderJobDownloading` emitted before each book with correct `currentBook` and `completedCount`
- `FolderJobDone` emitted at end with correct `results` map

### `test/ui/folder_download_notifier_test.dart` (rewrite)

- Initial state: `FolderJobIdle`
- `start()` transitions: `FolderJobScanning` → `FolderJobTreeReady`
- `start()` no-op when already scanning/downloading
- `confirmDownload()` transitions: `FolderJobTreeReady` → `FolderJobDownloading` → `FolderJobDone`
- `confirmDownload()` no-op when state is not `FolderJobTreeReady`
- `updateSelection()` updates `checkedBooks` in `FolderJobTreeReady`
- `cancel()` during scan → `FolderJobDone(wasCancelled: true)`
- `cancel()` during download → `FolderJobDone(wasCancelled: true)`
- `reset()` during tree-ready → state returns to `FolderJobIdle`

### `test/ui/folder_scan_screen_test.dart` (new)

- Shows "Scanning… (0 folders found)" initially
- Updates text when `foldersFound` increases
- Auto-navigates (replaces) when state becomes `FolderJobTreeReady`
- Pops when state becomes `FolderJobDone` (zero books / cancelled during scan)
- Cancel button calls `notifier.cancel()`

### `test/ui/folder_tree_screen_test.dart` (new)

- Selection mode: all books checked by default
- Unchecking a folder unchecks all its books
- Checking a folder checks all its books
- Indeterminate state when only some books checked
- Download button disabled when `checkedBooks` is empty
- Download button label shows count: "Download (N books)"
- Tapping Download calls `confirmDownload(checkedBooks)`
- Download mode: unchecked rows absent, checkboxes absent
- `currentBook` row shows spinner
- `done`/`skipped` row shows green checkmark
- `failed` row shows red warning; tapping opens AlertDialog with error text; tapping outside dismisses
- Pending rows show clock icon
- Progress bar value = completedCount / total
- Cancel button calls `notifier.cancel()`
- Done mode: Close button pops screen

### `test/ui/browse_screen_test.dart` (modify)

- Remove banner visibility tests
- AppBar button enabled when `FolderJobIdle`, disabled otherwise
- Tapping button navigates to scan screen (no dialog)

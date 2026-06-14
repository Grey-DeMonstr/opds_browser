# Folder Download Job — Design Spec

**Step:** 10 of 11
**Date:** 2026-06-14
**Status:** Approved

---

## Overview

Implement the "download everything" folder download feature: a BFS traversal of the current feed
and its sub-feeds, downloading every book found, with a persistent progress banner on every
BrowseScreen. Includes a small single-book dismiss fix (add a close button to the download
snackbar).

---

## Decisions made during brainstorming

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Job state lifetime | Global non-autoDispose `NotifierProvider` | Job survives navigation and screen rotation |
| Progress UI location | Bottom banner on **every** BrowseScreen while a job is active | User can browse other folders and still see progress |
| Summary dismissal | Manual DISMISS button (user-triggered) | Summary must not auto-disappear before user reads it |
| Job ↔ notifier communication | Callback-based (`void Function(FolderJobState)`) | Matches existing codebase patterns; easiest to test |
| Single-book snackbar | Add `showCloseIcon: true` | Minimal change; Flutter 3.x built-in |

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/domain/folder_download_job.dart` | Create | Pure BFS + download logic, testable with fakes |
| `lib/domain/download_utils.dart` | Modify | Add `folderPreferredLink` pure function |
| `lib/ui/providers.dart` | Modify | Add `FolderJobState`, `FolderDownloadNotifier`, `folderDownloadProvider` |
| `lib/ui/browse_screen.dart` | Modify | Wire Download-folder button + confirmation dialog; embed `FolderJobBanner` |
| `lib/ui/widgets/folder_job_banner.dart` | Create | Progress/summary banner widget |
| `test/domain/folder_download_job_test.dart` | Create | BFS, limits, cycle detection, concurrency, cancellation |
| `test/domain/download_utils_test.dart` | Modify | Add `folderPreferredLink` cases |
| `test/ui/folder_download_notifier_test.dart` | Create | Notifier state transitions |
| `test/ui/browse_screen_test.dart` | Modify | Banner visibility and Download-folder button states |

---

## 1. State model

```dart
sealed class FolderJobState { const FolderJobState(); }

class FolderJobIdle extends FolderJobState {
  const FolderJobIdle();
}

class FolderJobScanning extends FolderJobState {
  const FolderJobScanning({required this.foldersFound});
  final int foldersFound;
}

class FolderJobDownloading extends FolderJobState {
  const FolderJobDownloading({
    required this.completed,
    required this.total,
    required this.downloaded,
    required this.skipped,
    required this.failed,
  });
  final int completed; // downloaded + skipped + failed so far
  final int total;
  final int downloaded;
  final int skipped;
  final int failed;
}

class FolderJobDone extends FolderJobState {
  const FolderJobDone({
    required this.downloaded,
    required this.skipped,
    required this.failed,
    required this.stoppedAtLimit,
    this.wasCancelled = false,
  });
  final int downloaded;
  final int skipped;
  final int failed;
  final bool stoppedAtLimit;
  final bool wasCancelled;
}
```

`FolderJobState` lives in `providers.dart` alongside the other state types.

---

## 2. `folderPreferredLink` (new, `lib/domain/download_utils.dart`)

```dart
/// Like [preferredLink] but never returns null — used for folder downloads
/// where a picker cannot be shown.
AcquisitionLink folderPreferredLink(List<AcquisitionLink> links) {
  final preferred = preferredLink(links);
  if (preferred != null) return preferred;
  // No FB2 among multiple links — apply priority order
  const priority = ['EPUB', 'PDF', 'MOBI'];
  for (final label in priority) {
    final m = links.firstWhereOrNull((l) => l.formatLabel == label);
    if (m != null) return m;
  }
  return links.first;
}
```

`preferredLink` already handles: single link (return it), FB2.ZIP preferred over FB2, and returns
null only when there is no FB2 among multiple links. `folderPreferredLink` handles that null case
by applying EPUB > PDF > MOBI > first-listed.

---

## 3. `FolderDownloadJob` (`lib/domain/folder_download_job.dart`)

Pure Dart class with no Flutter or platform dependencies. Accepts fakes for all collaborators.

```dart
class FolderDownloadJob {
  FolderDownloadJob({
    required FeedRepository feedRepository,
    required BookDownloader downloader,
    required AppSettings settings,
    required void Function(FolderJobState) onProgress,
  });

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  Future<void> run(int catalogId, Uri startUrl) async { ... }
}
```

### Algorithm

**Phase 1 — BFS scanning:**

```
visited    = {}                       // normalized URL strings
queue      = [(startUrl, depth=0)]
tasks      = []                       // (BookEntry, AcquisitionLink)
folderCount = 0
stoppedAtLimit = false

while queue not empty and not cancelled:
  (url, depth) = queue.dequeue()
  key = normalizeUrl(url).toString()
  if key in visited: continue
  visited.add(key)

  if depth > 10 or folderCount >= 500 or tasks.length >= 2000:
    stoppedAtLimit = true
    continue

  folderCount++
  onProgress(FolderJobScanning(foldersFound: folderCount))

  feed = feedRepository.getFeed(catalogId, url)   // cache-first; errors → skip
  for entry in feed.entries:
    if NavigationEntry: queue.enqueue((entry.url, depth + 1))
    if BookEntry and tasks.length < 2000:
      tasks.add((entry, folderPreferredLink(entry.acquisitionLinks)))

if cancelled or tasks empty:
  onProgress(FolderJobDone(..., wasCancelled: _cancelled))
  return
```

Safety limits match the spec: max depth 10, max 500 folders, max 2000 books.
Inaccessible feeds (any exception from `getFeed`) are silently skipped.

**Phase 2 — download with concurrency 2:**

Worker-pool pattern: two async workers share a single `index` counter (safe in single-threaded Dart
because there is no `await` between the read and increment).

```dart
onProgress(FolderJobDownloading(completed: 0, total: tasks.length, ...));

var index = 0;
int downloaded = 0, skipped = 0, failed = 0;

Future<void> runWorker() async {
  while (!_cancelled) {
    final i = index++;
    if (i >= tasks.length) return;
    final (entry, link) = tasks[i];
    try {
      final result = await downloader.download(entry, link, settings);
      result == 'already_exists' ? skipped++ : downloaded++;
    } catch (_) { failed++; }
    onProgress(FolderJobDownloading(
      completed: downloaded + skipped + failed, total: tasks.length,
      downloaded: downloaded, skipped: skipped, failed: failed,
    ));
  }
}

await Future.wait([runWorker(), runWorker()]);

onProgress(FolderJobDone(
  downloaded: downloaded, skipped: skipped, failed: failed,
  stoppedAtLimit: stoppedAtLimit, wasCancelled: _cancelled,
));
```

When `cancel()` is called during downloading, the current in-flight downloads complete naturally
(the `await downloader.download(...)` is not interrupted); workers exit their while-loop on the
next iteration check.

---

## 4. Provider (`lib/ui/providers.dart` additions)

```dart
class FolderDownloadNotifier extends Notifier<FolderJobState> {
  FolderDownloadJob? _job;

  @override
  FolderJobState build() => const FolderJobIdle();

  Future<void> start(int catalogId, Uri url) async {
    if (state is! FolderJobIdle && state is! FolderJobDone) return;
    state = const FolderJobScanning(foldersFound: 0);

    final downloader = ref.read(bookDownloaderProvider);
    if (downloader == null) {
      state = const FolderJobDone(
          downloaded: 0, skipped: 0, failed: 0,
          stoppedAtLimit: false, wasCancelled: true);
      return;
    }

    _job = FolderDownloadJob(
      feedRepository: ref.read(feedRepositoryProvider),
      downloader: downloader,
      settings: ref.read(settingsProvider).requireValue,
      onProgress: (s) { state = s; },
    );

    await _job!.run(catalogId, url);
    _job = null;
  }

  void cancel() => _job?.cancel();
  void dismiss() => state = const FolderJobIdle();
}

final folderDownloadProvider =
    NotifierProvider<FolderDownloadNotifier, FolderJobState>(
        FolderDownloadNotifier.new);
```

**Key constraints:**
- Non-autoDispose — state survives navigation and rotation.
- `start()` is a no-op if a job is already `Scanning` or `Downloading` (guard against double-tap
  from multiple BrowseScreens seeing the enabled button simultaneously).
- `settings` is read once at job start; mid-download settings changes do not affect the in-flight job.
- `dismiss()` resets to `FolderJobIdle` after user reads the done summary.

---

## 5. UI

### `FolderJobBanner` (`lib/ui/widgets/folder_job_banner.dart`)

`ConsumerWidget`. Returns `SizedBox.shrink()` when state is `FolderJobIdle`. Otherwise renders a
`Material`-elevated bottom bar with message text + trailing button.

| State | Message | Trailing |
|-------|---------|----------|
| `FolderJobScanning` | "Scanning folders… (N found)" | CANCEL |
| `FolderJobDownloading` | "Downloading N of M · K skipped · J failed" (skipped/failed shown only when > 0) | CANCEL |
| `FolderJobDone` | "Cancelled. Downloaded: N · Skipped: K · Failed: J · Stopped at limit" (optional parts shown only when relevant) | DISMISS |

CANCEL calls `notifier.cancel()`. DISMISS calls `notifier.dismiss()`.

### BrowseScreen changes (`lib/ui/browse_screen.dart`)

**Body layout** — wrap existing body in a `Column`:

```dart
Column(children: [
  Expanded(child: /* existing ListView / loading / error / empty widgets */),
  const FolderJobBanner(),
])
```

`FolderJobBanner` collapses to zero height when `FolderJobIdle`, so it adds no visual footprint
when idle.

**Download-folder app bar button** — currently disabled; now reads `folderDownloadProvider` state
and enables only when `FolderJobIdle` or `FolderJobDone`:

```dart
IconButton(
  icon: const Icon(Icons.download_for_offline_outlined),
  tooltip: 'Download folder',
  onPressed: (jobState is FolderJobIdle || jobState is FolderJobDone) && feedLoaded
      ? () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Download folder'),
              content: const Text(
                'Download all books in this folder and its subfolders? '
                'This may be a large amount of data.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false),
                           child: const Text('CANCEL')),
                TextButton(onPressed: () => Navigator.pop(context, true),
                           child: const Text('DOWNLOAD')),
              ],
            ),
          );
          if (confirmed == true) {
            ref.read(folderDownloadProvider.notifier).start(catalogId, url);
          }
        }
      : null,
),
```

### Single-book snackbar dismiss fix

In `_BrowseContent`'s `ref.listen` on `lastDownloadResultProvider`, add `showCloseIcon: true` to
both SnackBar constructors (the "already downloaded" case and the "downloaded + Open" case):

```dart
SnackBar(showCloseIcon: true, content: Text(msg))
SnackBar(showCloseIcon: true, content: Text(msg), action: SnackBarAction(...))
```

---

## 6. Testing strategy

### `test/domain/folder_download_job_test.dart`

Uses `FakeFeedRepository` and `FakeBookDownloader` (already exist in the test suite or trivial to
add as local fakes).

**BFS traversal:**
- Navigation entries are followed; book entries are collected with correct link selected
- Mixed feed (nav + book entries) — both handled in one pass
- Cycle protection: same URL in two different branches → visited only once
- `onProgress` receives `FolderJobScanning(foldersFound: N)` once per unique folder

**Safety limits:**
- Depth > 10: entries at depth 11 are queued but not visited; `stoppedAtLimit = true` in done state
- Folders ≥ 500: 501st folder skipped; `stoppedAtLimit = true`
- Books ≥ 2000: 2001st book not added; `stoppedAtLimit = true`

**Download behaviour:**
- `already_exists` → `skipped` incremented, `downloaded` unchanged
- Exception from downloader → `failed` incremented, job continues
- `FolderJobDone` counts match actual outcomes

**Cancellation:**
- `cancel()` during scanning → emits `FolderJobDone(wasCancelled: true)`, BFS stops
- `cancel()` during downloading → workers exit loop, `wasCancelled: true` in done

**Error handling:**
- `FeedRepository.getFeed` throws → that folder is skipped silently; job continues

### `test/domain/download_utils_test.dart` additions

`folderPreferredLink`:
- Single link → returned
- FB2.ZIP + EPUB → FB2.ZIP returned (delegates to `preferredLink`)
- No FB2, has EPUB → EPUB returned
- No FB2, no EPUB, has PDF → PDF returned
- No FB2, no EPUB, no PDF, has MOBI → MOBI returned
- No priority match → first link returned

### `test/ui/folder_download_notifier_test.dart`

- Initial state is `FolderJobIdle`
- `start()` transitions through `Scanning → Downloading → Done`
- `start()` is a no-op when state is `FolderJobDownloading`
- `cancel()` propagates to `_job.cancel()` (use a fake job that records the call)
- `dismiss()` resets state to `FolderJobIdle`

### `test/ui/browse_screen_test.dart` additions

Override `folderDownloadProvider` with a fake state in each test:

- `FolderJobIdle` → banner absent, Download-folder button enabled (when feed loaded)
- `FolderJobScanning(foldersFound: 3)` → banner shows "Scanning folders… (3 found)", CANCEL button visible, Download-folder button disabled
- `FolderJobDownloading(completed: 2, total: 5, downloaded: 1, skipped: 1, failed: 0)` → banner shows "Downloading 2 of 5 · 1 skipped"
- `FolderJobDone(downloaded: 4, skipped: 1, failed: 0, stoppedAtLimit: false)` → banner shows summary, DISMISS button visible; tapping DISMISS calls `dismiss()`
- Tapping Download-folder button (when idle) shows confirmation dialog; confirming calls `start()`

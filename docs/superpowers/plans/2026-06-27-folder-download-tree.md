# Folder Download Tree Selection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace blind BFS-then-download with a two-stage flow: scan the full folder tree into a selection screen, then sequentially download only the checked books with a 5-second inter-book pause and live per-book progress on the same screen.

**Architecture:** `FolderDownloadJob` is rewritten: `run()` does the BFS scan and emits `FolderJobTreeReady` (tree + pre-checked book set); a new `download(checkedBooks)` method runs the sequential download with per-book `BookDownloadResult` updates. `FolderDownloadNotifier` gains `confirmDownload`, `updateSelection`, and `reset` with a generation counter to discard stale async progress. Two new full-screen routes replace the old inline banner: `FolderScanScreen` (scan progress) and `FolderTreeScreen` (selection → download → done in one widget). `FolderJobBanner` is deleted.

**Tech Stack:** Flutter, Riverpod plain `Notifier`, go_router, flutter_test (host-only, no device).

## Global Constraints

- Android only — no iOS code.
- `dart run tool/check.dart` must pass (clean analyze + all tests) before any task is considered done.
- TDD mandatory: write the failing test first, run it to confirm failure, then implement.
- All tests run on host with `flutter test` — no emulator, no `integration_test`.
- Pure Dart in `lib/domain/` and `lib/data/` — no Flutter imports.
- Riverpod: plain `Notifier`/`AsyncNotifier`, no codegen.
- Navigation via `go_router`.

---

## File Map

| File | Action |
|------|--------|
| `lib/data/folder_download_job.dart` | Rewrite: new tree types, result types, new state classes, new `run()` + `download()` methods |
| `lib/ui/providers.dart` | Modify: `FolderDownloadNotifier` — add `confirmDownload`, `updateSelection`, `reset`; remove `dismiss` |
| `lib/ui/folder_scan_screen.dart` | Create |
| `lib/ui/folder_tree_screen.dart` | Create |
| `lib/app.dart` | Modify: add two new routes |
| `lib/ui/browse_screen.dart` | Modify: remove banner, update button guard + nav |
| `lib/ui/widgets/folder_job_banner.dart` | Delete (stub in Task 2, deleted in Task 9) |
| `test/data/folder_download_job_test.dart` | Rewrite |
| `test/ui/folder_download_notifier_test.dart` | Rewrite |
| `test/ui/folder_scan_screen_test.dart` | Create |
| `test/ui/folder_tree_screen_test.dart` | Create |
| `test/ui/browse_screen_test.dart` | Modify |

---

### Task 1: Tree model types and download result types

Add new domain types to `lib/data/folder_download_job.dart` — purely additive, nothing existing changes.

**Files:**
- Modify: `lib/data/folder_download_job.dart`
- Test: `test/data/folder_download_job_test.dart`

**Interfaces:**
- Produces: `DownloadTreeNode` (sealed), `DownloadBook`, `DownloadFolder`, `BookDownloadStatus` (enum), `BookDownloadResult` — used by every subsequent task.
- Produces: updated `DownloadFn` typedef that includes `{String? inferredSeries}`.

- [ ] **Step 1: Write failing tests**

Append a new group to `test/data/folder_download_job_test.dart`:

```dart
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

// (existing imports + fakes stay; add this group at the bottom)

group('tree model types', () {
  test('DownloadBook holds entry, link, optional series', () {
    final link = AcquisitionLink(
      url: Uri.parse('http://x.com/b.epub'),
      mimeType: 'application/epub+zip',
      formatLabel: 'EPUB',
    );
    final entry = BookEntry(title: 'T', authors: const ['A'], acquisitionLinks: [link]);
    final book = DownloadBook(entry: entry, link: link, inferredSeries: 'S');
    expect(book.entry.title, 'T');
    expect(book.link.formatLabel, 'EPUB');
    expect(book.inferredSeries, 'S');
  });

  test('DownloadFolder holds title and children list', () {
    final folder = DownloadFolder(title: 'F', children: []);
    expect(folder.title, 'F');
    expect(folder.children, isEmpty);
  });

  test('BookDownloadResult.failed carries error string', () {
    const r = BookDownloadResult(status: BookDownloadStatus.failed, error: 'timeout');
    expect(r.status, BookDownloadStatus.failed);
    expect(r.error, 'timeout');
  });

  test('BookDownloadResult.done has null error', () {
    const r = BookDownloadResult(status: BookDownloadStatus.done);
    expect(r.error, isNull);
  });
});
```

- [ ] **Step 2: Run test — confirm compile failure**

```powershell
flutter test test/data/folder_download_job_test.dart
```
Expected: compile error — `DownloadBook`, `DownloadFolder`, `BookDownloadResult`, `BookDownloadStatus` undefined.

- [ ] **Step 3: Add types to `lib/data/folder_download_job.dart`**

Update the `DownloadFn` typedef (add `inferredSeries` named param):

```dart
typedef DownloadFn = Future<String> Function(
    BookEntry entry, AcquisitionLink link, AppSettings settings,
    {String? inferredSeries});
```

Insert the following block immediately after the `DownloadFn` typedef and before `// ── State`:

```dart
// ── Tree model ────────────────────────────────────────────────────────────────

sealed class DownloadTreeNode {
  const DownloadTreeNode();
}

class DownloadBook extends DownloadTreeNode {
  const DownloadBook({
    required this.entry,
    required this.link,
    this.inferredSeries,
  });
  final BookEntry entry;
  final AcquisitionLink link;
  final String? inferredSeries;
}

class DownloadFolder extends DownloadTreeNode {
  DownloadFolder({required this.title, required this.children});
  final String title;
  final List<DownloadTreeNode> children;
}

// ── Download result ───────────────────────────────────────────────────────────

enum BookDownloadStatus { downloading, done, skipped, failed }

class BookDownloadResult {
  const BookDownloadResult({required this.status, this.error});
  final BookDownloadStatus status;
  final String? error;
}
```

Note: `DownloadFolder` uses a non-`const` constructor because its `children` list must be mutably populated during BFS.

- [ ] **Step 4: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/folder_download_job.dart test/data/folder_download_job_test.dart
git commit -m "feat: add DownloadTreeNode and BookDownloadResult types for folder download tree"
```

---

### Task 2: Replace state classes and fix compilation breakages

`FolderJobDownloading` and `FolderJobDone` get new shapes; `FolderJobTreeReady` is added. This breaks `FolderJobBanner` and test assertions — fix both here.

**Files:**
- Modify: `lib/data/folder_download_job.dart` (replace state section)
- Modify: `lib/ui/widgets/folder_job_banner.dart` (stub to avoid compile error)
- Modify: `lib/ui/providers.dart` (update `FolderDownloadNotifier` to compile)
- Modify: `test/data/folder_download_job_test.dart` (update broken assertions)
- Modify: `test/ui/folder_download_notifier_test.dart` (update broken assertions)

**Interfaces:**
- Produces: finalized `FolderJobState` sealed hierarchy used by all remaining tasks.

- [ ] **Step 1: Replace state classes in `lib/data/folder_download_job.dart`**

Replace the entire `// ── State` section (lines 14–57 in the original) with:

```dart
// ── State ─────────────────────────────────────────────────────────────────────

sealed class FolderJobState {
  const FolderJobState();
}

class FolderJobIdle extends FolderJobState {
  const FolderJobIdle();
}

class FolderJobScanning extends FolderJobState {
  const FolderJobScanning({required this.foldersFound});
  final int foldersFound;
}

/// Scan complete — awaiting user selection.
class FolderJobTreeReady extends FolderJobState {
  const FolderJobTreeReady({
    required this.root,
    required this.checkedBooks,
    this.stoppedAtLimit = false,
  });
  final DownloadTreeNode root;
  final Set<Uri> checkedBooks;
  final bool stoppedAtLimit;

  FolderJobTreeReady copyWith({Set<Uri>? checkedBooks}) => FolderJobTreeReady(
        root: root,
        checkedBooks: checkedBooks ?? this.checkedBooks,
        stoppedAtLimit: stoppedAtLimit,
      );
}

/// Download in progress — root is the checked-only subtree.
class FolderJobDownloading extends FolderJobState {
  const FolderJobDownloading({
    required this.root,
    required this.results,
    required this.total,
    required this.completedCount,
    this.currentBook,
  });
  final DownloadTreeNode root;
  final Uri? currentBook;
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

- [ ] **Step 2: Stub `FolderJobBanner` to eliminate compile errors**

Replace the entire content of `lib/ui/widgets/folder_job_banner.dart`:

```dart
import 'package:flutter/material.dart';

// Temporary stub — deleted in Task 9.
class FolderJobBanner extends StatelessWidget {
  const FolderJobBanner({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

- [ ] **Step 3: Update `FolderDownloadNotifier` in `lib/ui/providers.dart` to compile**

The `start()` method currently emits old-shaped `FolderJobDone`. Update the error-path emission (the `downloader == null` case):

```dart
// replace the old FolderJobDone(...) call in start() with:
state = FolderJobDone(
  root: DownloadFolder(title: '', children: []),
  results: const {},
  wasCancelled: true,
  stoppedAtLimit: false,
);
```

Also update the `FolderDownloadJob` constructor call — rename `download:` to `downloadFn:`:

```dart
_job = FolderDownloadJob(
  feedRepository: ref.read(feedRepositoryProvider),
  downloadFn: downloader.download,  // was: download:
  settings: ref.read(settingsProvider).requireValue,
  onProgress: (s) { state = s; },
);
```

Keep `dismiss()` for now (removed in Task 5).

- [ ] **Step 4: Update broken test assertions**

In `test/data/folder_download_job_test.dart`, the BFS/download/cancel groups reference old `FolderJobDone` fields (`downloaded`, `skipped`, `failed`). Temporarily simplify them to only assert `wasCancelled` and `stoppedAtLimit` (the detailed counts come back in Task 4):

```dart
// 'visits root and follows navigation entries'
final done = states.last as FolderJobDone;
expect(done.wasCancelled, false);
expect(done.stoppedAtLimit, false);

// 'cycle protection — same URL visited once'
expect(repo.callCount, 1);
final done2 = states.last as FolderJobDone;
expect(done2.wasCancelled, false);

// 'inaccessible feed is silently skipped'
final done3 = states.last as FolderJobDone;
expect(done3.wasCancelled, false);

// 'empty feed emits FolderJobDone with zeros'
final done4 = states.last as FolderJobDone;
expect(done4.wasCancelled, false);
expect(done4.stoppedAtLimit, false);

// 'depth > 10 skipped, stoppedAtLimit = true'
final done5 = states.last as FolderJobDone;
expect(done5.stoppedAtLimit, isTrue);

// '500th+ folder is skipped, stoppedAtLimit = true'
final done6 = states.last as FolderJobDone;
expect(done6.stoppedAtLimit, isTrue);

// '2000 books' — update to check FolderJobDone.stoppedAtLimit; remove downloadCount checks
// since concurrent download no longer exists; replace body with:
final done7 = states.last as FolderJobDone;
expect(done7.stoppedAtLimit, isTrue);

// Download phase group — remove all assertions referencing done.downloaded/skipped/failed
// Replace each test body with just: expect(states.last, isA<FolderJobDone>());

// Cancellation group — keep wasCancelled check:
final doneC = states.last as FolderJobDone;
expect(doneC.wasCancelled, isTrue);
// Remove: expect(downloadCount, lessThanOrEqualTo(4))
```

In `test/ui/folder_download_notifier_test.dart`, update:

```dart
// 'start() with empty feed ends as FolderJobDone(downloaded: 0)' → rename + simplify:
test('start() with empty feed ends as FolderJobDone', () async {
  final c = _container();
  await c.read(settingsProvider.future);
  await c.read(folderDownloadProvider.notifier).start(1, Uri.parse('http://x.com'));
  expect(c.read(folderDownloadProvider), isA<FolderJobDone>());
});
// All other tests remain valid as-is (they only check isA<> types).
```

- [ ] **Step 5: Run check**

```powershell
dart run tool/check.dart
```
Expected: clean analyze + all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/data/folder_download_job.dart lib/ui/widgets/folder_job_banner.dart lib/ui/providers.dart test/data/folder_download_job_test.dart test/ui/folder_download_notifier_test.dart
git commit -m "refactor: replace FolderJobState classes with tree-aware state model"
```

---

### Task 3: Rewrite `FolderDownloadJob.run()` — BFS scan builds a tree

`run()` now produces a `DownloadTreeNode` tree and emits `FolderJobTreeReady`. Single-book folder collapsing + empty-folder pruning applied after BFS.

**Files:**
- Modify: `lib/data/folder_download_job.dart` (rewrite `run()` and the `FolderDownloadJob` class shape; add helpers)
- Test: `test/data/folder_download_job_test.dart` (replace scan group with tree-building tests)

**Interfaces:**
- Produces: `FolderDownloadJob.run(int catalogId, Uri startUrl)` → emits `FolderJobTreeReady` or `FolderJobDone` (empty/cancelled).
- Produces: instance fields `_stoppedAtLimit` and `_scannedRoot` (used by `download()` in Task 4).

- [ ] **Step 1: Write failing tests for new `run()` behaviour**

Replace the entire `'BFS scanning'` and `'safety limits'` groups in `test/data/folder_download_job_test.dart` with the following. Also update `_makeJob` helper to accept the new constructor signature:

```dart
// ── Updated helpers ───────────────────────────────────────────────────────────

FolderDownloadJob _makeJob(
  _FakeFeedRepository repo, {
  DownloadFn? downloadFn,
  required List<FolderJobState> states,
  Duration downloadDelay = Duration.zero,
}) =>
    FolderDownloadJob(
      feedRepository: repo,
      downloadFn: downloadFn ?? _noOp,
      settings: _settings,
      onProgress: states.add,
      downloadDelay: downloadDelay,
    );

// ── Scan / tree-building tests ────────────────────────────────────────────────

group('scan phase — tree building', () {
  test('single book at root collapses to DownloadBook', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final ready = states.last as FolderJobTreeReady;
    expect(ready.root, isA<DownloadBook>());
    expect((ready.root as DownloadBook).entry.title, 'Book 1');
  });

  test('two books at root stay wrapped in DownloadFolder', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1'), _book('2')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final ready = states.last as FolderJobTreeReady;
    expect(ready.root, isA<DownloadFolder>());
    expect((ready.root as DownloadFolder).children.length, 2);
  });

  test('nav chain with single book collapses recursively', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    final sub = Uri.parse('http://example.com/sub');
    repo.addFeed(root, [_nav('/sub')]);
    repo.addFeed(sub, [_book('1')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    // root → folder(sub) → book1: folder collapsed twice → book1
    expect(states.last, isA<FolderJobTreeReady>());
    expect((states.last as FolderJobTreeReady).root, isA<DownloadBook>());
  });

  test('mixed root (nav + book) builds two-child folder', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    final sub = Uri.parse('http://example.com/sub');
    repo.addFeed(root, [_nav('/sub'), _book('direct')]);
    repo.addFeed(sub, [_book('nested1'), _book('nested2')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final ready = states.last as FolderJobTreeReady;
    final folder = ready.root as DownloadFolder;
    // After collapse: sub-folder has 2 children (no collapse) + direct book
    expect(folder.children.length, 2);
  });

  test('checkedBooks contains all book link URLs', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1'), _book('2')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final ready = states.last as FolderJobTreeReady;
    expect(ready.checkedBooks.length, 2);
  });

  test('cycle: same URL visited once, empty nav branch pruned', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_nav('/root'), _book('1')]); // nav points back to root

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    expect(repo.callCount, 1); // fetched root only once
    // Empty nav branch is pruned; only the book remains → collapses to DownloadBook
    final ready = states.last as FolderJobTreeReady;
    expect(ready.root, isA<DownloadBook>());
  });

  test('inaccessible feed is skipped; accessible feed still included', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_nav('/bad'), _nav('/good')]);
    repo.addError(Uri.parse('http://example.com/bad'), Exception('timeout'));
    repo.addFeed(Uri.parse('http://example.com/good'), [_book('ok')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final ready = states.last as FolderJobTreeReady;
    expect(ready.checkedBooks.length, 1);
  });

  test('empty root feed emits FolderJobDone (not FolderJobTreeReady)', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, []);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    expect(states.last, isA<FolderJobDone>());
    final done = states.last as FolderJobDone;
    expect(done.wasCancelled, false);
    expect(done.stoppedAtLimit, false);
  });

  test('depth > 10 skipped; stoppedAtLimit = true in FolderJobTreeReady', () async {
    final repo = _FakeFeedRepository();
    // f0(depth=0) → f1 → ... → f10(depth=10) → f11(depth=11, book inside)
    for (var i = 0; i <= 10; i++) {
      repo.addFeed(
        Uri.parse('http://example.com/f$i'),
        [NavigationEntry(title: 'F', url: Uri.parse('http://example.com/f${i + 1}'))],
      );
    }
    // f11 has a book but depth 11 is over limit
    repo.addFeed(Uri.parse('http://example.com/f11'), [_book('deep')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, Uri.parse('http://example.com/f0'));

    // No books found (f11 was skipped) → FolderJobDone
    expect(states.last, isA<FolderJobDone>());
    expect((states.last as FolderJobDone).stoppedAtLimit, isTrue);
  });

  test('500+ folders: stoppedAtLimit = true', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    final subs = List.generate(
      500,
      (i) => NavigationEntry(title: 'F$i', url: Uri.parse('http://example.com/sub/$i')),
    );
    repo.addFeed(root, subs);
    for (var i = 0; i < 500; i++) {
      repo.addFeed(Uri.parse('http://example.com/sub/$i'), []);
    }

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    // All 500 sub-feeds are empty; result is FolderJobDone (no books) with stoppedAtLimit
    expect(states.last, isA<FolderJobDone>());
    expect((states.last as FolderJobDone).stoppedAtLimit, isTrue);
  });

  test('at most 2000 books collected; stoppedAtLimit = true in FolderJobTreeReady', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, List.generate(2001, (i) => _book('$i')));

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final ready = states.last as FolderJobTreeReady;
    expect(ready.checkedBooks.length, 2000);
    expect(ready.stoppedAtLimit, isTrue);
  });

  test('cancel during scan: FolderJobDone with wasCancelled = true', () async {
    final repo = _CancellingFeedRepository(cancelAfterCalls: 2);
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_nav('/sub')]);
    repo.addFeed(Uri.parse('http://example.com/sub'), [_book('1')]);

    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: _noOp,
      settings: _settings,
      onProgress: states.add,
    );
    repo.job = job;
    await job.run(1, root);

    expect(states.last, isA<FolderJobDone>());
    expect((states.last as FolderJobDone).wasCancelled, isTrue);
  });

  test('FolderJobScanning emitted with increasing foldersFound', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    final sub = Uri.parse('http://example.com/sub');
    repo.addFeed(root, [_nav('/sub')]);
    repo.addFeed(sub, [_book('1')]);

    final states = <FolderJobState>[];
    await _makeJob(repo, states: states).run(1, root);

    final scanning = states.whereType<FolderJobScanning>().toList();
    expect(scanning.length, 2); // root + sub
    expect(scanning.last.foldersFound, 2);
  });
});
```

- [ ] **Step 2: Run tests — confirm failures**

```powershell
flutter test test/data/folder_download_job_test.dart
```
Expected: failures in new group (old `run()` emits `FolderJobDone`, not `FolderJobTreeReady`). Also `downloadDelay` param missing.

- [ ] **Step 3: Rewrite `FolderDownloadJob` class with new `run()` implementation**

Replace the entire `// ── Job` section in `lib/data/folder_download_job.dart` with:

```dart
// ── Job ───────────────────────────────────────────────────────────────────────

class FolderDownloadJob {
  FolderDownloadJob({
    required FeedRepository feedRepository,
    required DownloadFn downloadFn,
    required AppSettings settings,
    required void Function(FolderJobState) onProgress,
    Duration downloadDelay = const Duration(seconds: 5),
  })  : _feedRepository = feedRepository,
        _downloadFn = downloadFn,
        _settings = settings,
        _onProgress = onProgress,
        _downloadDelay = downloadDelay;

  final FeedRepository _feedRepository;
  final DownloadFn _downloadFn;
  final AppSettings _settings;
  final void Function(FolderJobState) _onProgress;
  final Duration _downloadDelay;

  bool _cancelled = false;
  bool _stoppedAtLimit = false;
  DownloadTreeNode? _scannedRoot;

  void cancel() => _cancelled = true;

  /// Phase 1: BFS scan → emits FolderJobTreeReady, or FolderJobDone if empty/cancelled.
  Future<void> run(int catalogId, Uri startUrl) async {
    final visited = <String>{};
    // Queue: (url, depth, mutable children list to populate with entries from that url)
    final queue = Queue<(Uri, int, List<DownloadTreeNode>)>();
    _stoppedAtLimit = false;
    var folderCount = 0;
    var bookCount = 0;

    final rootChildren = <DownloadTreeNode>[];
    queue.add((startUrl, 0, rootChildren));

    while (queue.isNotEmpty && !_cancelled) {
      final (url, depth, targetChildren) = queue.removeFirst();
      final key = normalizeUrl(url);
      if (visited.contains(key)) continue;
      visited.add(key);

      if (depth > 10 || folderCount >= 500 || bookCount >= 2000) {
        _stoppedAtLimit = true;
        continue;
      }

      folderCount++;
      _onProgress(FolderJobScanning(foldersFound: folderCount));

      CachedFeed cached;
      try {
        cached = await _feedRepository.getFeed(catalogId, url);
      } catch (_) {
        continue;
      }

      final inferredSeries = inferSeriesFromUrl(url);

      for (final entry in cached.feed.entries) {
        if (entry is NavigationEntry) {
          final folderChildren = <DownloadTreeNode>[];
          targetChildren.add(DownloadFolder(title: entry.title, children: folderChildren));
          queue.add((entry.url, depth + 1, folderChildren));
        } else if (entry is BookEntry &&
            entry.acquisitionLinks.isNotEmpty &&
            bookCount < 2000) {
          targetChildren.add(DownloadBook(
            entry: entry,
            link: folderPreferredLink(entry.acquisitionLinks),
            inferredSeries: inferredSeries,
          ));
          bookCount++;
        }
      }
      if (bookCount >= 2000) _stoppedAtLimit = true;
    }

    // Build root node
    final rawRoot = rootChildren.length == 1
        ? rootChildren.first
        : DownloadFolder(title: '', children: rootChildren);

    final collapsed = _collapseTree(rawRoot);

    if (_cancelled || bookCount == 0) {
      _onProgress(FolderJobDone(
        root: collapsed ?? DownloadFolder(title: '', children: []),
        results: const {},
        wasCancelled: _cancelled,
        stoppedAtLimit: _stoppedAtLimit,
      ));
      return;
    }

    _scannedRoot = collapsed!;
    final allBookUrls = _collectBookUrls(_scannedRoot!);
    _onProgress(FolderJobTreeReady(
      root: _scannedRoot!,
      checkedBooks: allBookUrls,
      stoppedAtLimit: _stoppedAtLimit,
    ));
  }

  /// Phase 2: sequential download — call after run() emits FolderJobTreeReady.
  Future<void> download(Set<Uri> checkedBooks) async {
    // Implemented in Task 4
  }
}

// ── Tree helpers ──────────────────────────────────────────────────────────────

/// Collapse single-child folders and prune empty folders.
/// Returns null when the node (and all its descendants) are empty.
DownloadTreeNode? _collapseTree(DownloadTreeNode node) {
  if (node is DownloadBook) return node;
  final folder = node as DownloadFolder;
  final collapsed =
      folder.children.map(_collapseTree).whereType<DownloadTreeNode>().toList();
  if (collapsed.isEmpty) return null;
  if (collapsed.length == 1) return collapsed.first;
  return DownloadFolder(title: folder.title, children: collapsed);
}

Set<Uri> _collectBookUrls(DownloadTreeNode node) {
  if (node is DownloadBook) return {node.link.url};
  return (node as DownloadFolder).children.fold(
    <Uri>{},
    (acc, child) => acc..addAll(_collectBookUrls(child)),
  );
}

/// Filter tree to only nodes whose subtree intersects [checkedBooks].
DownloadTreeNode? _filterTree(DownloadTreeNode node, Set<Uri> checkedBooks) {
  if (node is DownloadBook) {
    return checkedBooks.contains(node.link.url) ? node : null;
  }
  final folder = node as DownloadFolder;
  final filtered =
      folder.children.map((c) => _filterTree(c, checkedBooks)).whereType<DownloadTreeNode>().toList();
  if (filtered.isEmpty) return null;
  if (filtered.length == 1) return filtered.first;
  return DownloadFolder(title: folder.title, children: filtered);
}

List<DownloadBook> _collectTasks(DownloadTreeNode node) {
  if (node is DownloadBook) return [node];
  return (node as DownloadFolder).children.expand(_collectTasks).toList();
}
```

- [ ] **Step 4: Run tests**

```powershell
dart run tool/check.dart
```
Expected: new scan tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/folder_download_job.dart test/data/folder_download_job_test.dart
git commit -m "feat: rewrite FolderDownloadJob.run() to build DownloadTreeNode tree"
```

---

### Task 4: Implement `FolderDownloadJob.download()` — sequential with 5-second pause

**Files:**
- Modify: `lib/data/folder_download_job.dart` (implement `download()`)
- Test: `test/data/folder_download_job_test.dart` (add download phase group)

**Interfaces:**
- Produces: `FolderDownloadJob.download(Set<Uri> checkedBooks)` → emits `FolderJobDownloading` per book, then `FolderJobDone`.

- [ ] **Step 1: Write failing tests for `download()`**

Add a new group at the bottom of `test/data/folder_download_job_test.dart` (after the scan group). Each test calls `run()` first (to populate `_scannedRoot`), then `download()`:

```dart
group('download phase', () {
  Future<void> _runThenDownload(
    FolderDownloadJob job,
    _FakeFeedRepository repo,
    Uri root, {
    Set<Uri>? checkedBooks,
  }) async {
    final states = <FolderJobState>[];
    // Replace job's onProgress temporarily via a local job
    // (We reuse the helper: this group creates jobs with an accessible state list)
    await job.run(1, root);
    final ready = states.isEmpty
        ? null
        : states.whereType<FolderJobTreeReady>().lastOrNull;
    await job.download(checkedBooks ?? ready?.checkedBooks ?? {});
  }

  test('successful download: BookDownloadStatus.done', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1')]);

    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async => 'content://ok',
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);

    final done = states.last as FolderJobDone;
    expect(done.results.length, 1);
    expect(done.results.values.first.status, BookDownloadStatus.done);
  });

  test('already_exists: BookDownloadStatus.skipped', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1')]);

    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async => 'already_exists',
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);

    final done = states.last as FolderJobDone;
    expect(done.results.values.first.status, BookDownloadStatus.skipped);
  });

  test('download exception: BookDownloadStatus.failed with error; job continues', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('bad'), _book('good')]);

    var calls = 0;
    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async {
        calls++;
        if (e.title == 'Book bad') throw Exception('network error');
        return 'content://ok';
      },
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);

    final done = states.last as FolderJobDone;
    expect(calls, 2); // both attempted
    final statuses = done.results.values.map((r) => r.status).toSet();
    expect(statuses, containsAll([BookDownloadStatus.failed, BookDownloadStatus.done]));
    final failedResult = done.results.values.firstWhere((r) => r.status == BookDownloadStatus.failed);
    expect(failedResult.error, contains('network error'));
  });

  test('FolderJobDownloading emitted before each book with currentBook set', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1'), _book('2')]);

    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async => 'content://ok',
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);

    final downloading = states.whereType<FolderJobDownloading>().toList();
    expect(downloading.length, 2); // one before each book
    for (final d in downloading) {
      expect(d.currentBook, isNotNull);
    }
    expect(downloading.last.completedCount, 1); // second book's pre-emit shows 1 done
  });

  test('no delay after the last book', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1')]);

    var delayCount = 0;
    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async => 'content://ok',
      settings: _settings,
      onProgress: states.add,
      downloadDelay: const Duration(milliseconds: 1),
    );
    // We just check it completes quickly (no hanging delay after last book)
    final sw = Stopwatch()..start();
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);
    sw.stop();
    // With 1ms delay and NO trailing delay, completion should be well under 100ms
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('only checked books are downloaded', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, [_book('1'), _book('2'), _book('3')]);

    var calls = 0;
    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async { calls++; return 'content://ok'; },
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    // Uncheck one book
    final oneBook = ready.checkedBooks.first;
    final subset = ready.checkedBooks.where((u) => u != oneBook).toSet();
    await job.download(subset);

    expect(calls, 2); // only 2 downloaded
    final done = states.last as FolderJobDone;
    expect(done.results.length, 2);
  });

  test('cancel during download: remaining books not started; wasCancelled = true', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, List.generate(5, (i) => _book('$i')));

    var downloadCount = 0;
    FolderDownloadJob? job;
    final states = <FolderJobState>[];
    job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async {
        downloadCount++;
        if (downloadCount == 2) job!.cancel();
        return 'content://ok';
      },
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);

    final done = states.last as FolderJobDone;
    expect(done.wasCancelled, isTrue);
    expect(downloadCount, lessThan(5)); // cancelled after 2nd book
  });

  test('FolderJobDone.stoppedAtLimit preserved from scan phase', () async {
    final repo = _FakeFeedRepository();
    final root = Uri.parse('http://example.com/root');
    repo.addFeed(root, List.generate(2001, (i) => _book('$i')));

    final states = <FolderJobState>[];
    final job = FolderDownloadJob(
      feedRepository: repo,
      downloadFn: (e, l, s, {inferredSeries}) async => 'content://ok',
      settings: _settings,
      onProgress: states.add,
      downloadDelay: Duration.zero,
    );
    await job.run(1, root);
    final ready = states.whereType<FolderJobTreeReady>().last;
    await job.download(ready.checkedBooks);

    final done = states.last as FolderJobDone;
    expect(done.stoppedAtLimit, isTrue);
  });
});
```

- [ ] **Step 2: Run tests — confirm failures**

```powershell
flutter test test/data/folder_download_job_test.dart
```
Expected: failures in `download phase` group (stub `download()` does nothing).

- [ ] **Step 3: Implement `download()` in `lib/data/folder_download_job.dart`**

Replace the stub `download()` body with:

```dart
Future<void> download(Set<Uri> checkedBooks) async {
  if (_scannedRoot == null || checkedBooks.isEmpty) {
    _onProgress(FolderJobDone(
      root: DownloadFolder(title: '', children: []),
      results: const {},
      wasCancelled: _cancelled,
      stoppedAtLimit: _stoppedAtLimit,
    ));
    return;
  }

  final displayRoot = _filterTree(_scannedRoot!, checkedBooks) ??
      DownloadFolder(title: '', children: []);
  final tasks = _collectTasks(displayRoot);
  final results = <Uri, BookDownloadResult>{};

  for (var i = 0; i < tasks.length; i++) {
    if (_cancelled) break;

    final task = tasks[i];
    _onProgress(FolderJobDownloading(
      root: displayRoot,
      currentBook: task.link.url,
      results: Map.unmodifiable(results),
      total: tasks.length,
      completedCount: results.length,
    ));

    try {
      final outcome = await _downloadFn(
        task.entry, task.link, _settings,
        inferredSeries: task.inferredSeries,
      );
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

    if (!_cancelled && i < tasks.length - 1) {
      await Future.delayed(_downloadDelay);
    }
  }

  _onProgress(FolderJobDone(
    root: displayRoot,
    results: Map.unmodifiable(results),
    wasCancelled: _cancelled,
    stoppedAtLimit: _stoppedAtLimit,
  ));
}
```

- [ ] **Step 4: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/folder_download_job.dart test/data/folder_download_job_test.dart
git commit -m "feat: implement FolderDownloadJob.download() — sequential with 5s inter-book pause"
```

---

### Task 5: Update `FolderDownloadNotifier`

Add `confirmDownload`, `updateSelection`, `reset`; add a generation counter to prevent stale async progress from landing after `reset`; remove `dismiss`.

**Files:**
- Modify: `lib/ui/providers.dart`
- Test: `test/ui/folder_download_notifier_test.dart` (rewrite)

**Interfaces:**
- Produces: `FolderDownloadNotifier.start(catalogId, url)`, `.confirmDownload(checkedBooks)`, `.updateSelection(checkedBooks)`, `.reset()`, `.cancel()`.

- [ ] **Step 1: Write failing tests**

Replace `test/ui/folder_download_notifier_test.dart` entirely:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _EmptyFeedRepo implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
          {bool forceRefresh = false}) async =>
      CachedFeed(
        feed: const ParsedFeed(title: 'Empty', entries: []),
        fetchedAt: DateTime.now(),
        fromCache: false,
      );
}

class _OneFeedRepo implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
          {bool forceRefresh = false}) async =>
      CachedFeed(
        feed: ParsedFeed(
          title: 'Feed',
          entries: [
            BookEntry(
              title: 'B',
              authors: const ['A'],
              acquisitionLinks: [
                AcquisitionLink(
                  url: Uri.parse('http://x.com/b.epub'),
                  mimeType: 'application/epub+zip',
                  formatLabel: 'EPUB',
                ),
              ],
            ),
          ],
        ),
        fetchedAt: DateTime.now(),
        fromCache: false,
      );
}

class _SlowFeedRepo implements FeedRepository {
  final _completer = Completer<CachedFeed>();
  void complete() => _completer.complete(CachedFeed(
        feed: const ParsedFeed(title: 'Done', entries: []),
        fetchedAt: DateTime.now(),
        fromCache: false,
      ));
  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
          {bool forceRefresh = false}) =>
      _completer.future;
}

class _FakeDownloadStorage implements DownloadStorage {
  @override
  Future<bool> exists(List<String> s, String f) async => false;
  @override
  Future<String> write(
      List<String> s, String f, Stream<List<int>> b, String mimeType) async {
    await b.drain<void>();
    return 'content://fake';
  }
}

class _ConstSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> load() async =>
      const AppSettings(target: SystemDownloads());
  @override
  Future<void> save(AppSettings s) async {}
}

// ── Container builder ─────────────────────────────────────────────────────────

ProviderContainer _container({FeedRepository? feedRepo}) {
  final c = ProviderContainer(overrides: [
    feedRepositoryProvider.overrideWithValue(feedRepo ?? _EmptyFeedRepo()),
    downloadStorageProvider.overrideWith((ref) => _FakeDownloadStorage()),
    settingsRepositoryProvider.overrideWithValue(_ConstSettingsRepo()),
    safPermissionCheckerProvider.overrideWithValue((_) async => true),
  ]);
  addTearDown(c.dispose);
  return c;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('initial state is FolderJobIdle', () {
    final c = _container();
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });

  test('start() with empty feed ends as FolderJobDone', () async {
    final c = _container();
    await c.read(settingsProvider.future);
    await c.read(folderDownloadProvider.notifier).start(1, Uri.parse('http://x.com'));
    expect(c.read(folderDownloadProvider), isA<FolderJobDone>());
  });

  test('start() with one book ends as FolderJobTreeReady', () async {
    final c = _container(feedRepo: _OneFeedRepo());
    await c.read(settingsProvider.future);
    await c.read(folderDownloadProvider.notifier).start(1, Uri.parse('http://x.com'));
    expect(c.read(folderDownloadProvider), isA<FolderJobTreeReady>());
  });

  test('start() no-op when already scanning', () async {
    final slowRepo = _SlowFeedRepo();
    final c = _container(feedRepo: slowRepo);
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);

    final firstFuture = notifier.start(1, Uri.parse('http://x.com'));
    expect(c.read(folderDownloadProvider), isA<FolderJobScanning>());

    await notifier.start(1, Uri.parse('http://x.com/other'));
    expect(c.read(folderDownloadProvider), isA<FolderJobScanning>());

    slowRepo.complete();
    await firstFuture;
  });

  test('updateSelection updates checkedBooks in FolderJobTreeReady', () async {
    final c = _container(feedRepo: _OneFeedRepo());
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);
    await notifier.start(1, Uri.parse('http://x.com'));

    expect(c.read(folderDownloadProvider), isA<FolderJobTreeReady>());
    notifier.updateSelection({}); // uncheck all

    final ready = c.read(folderDownloadProvider) as FolderJobTreeReady;
    expect(ready.checkedBooks, isEmpty);
  });

  test('confirmDownload transitions through Downloading to Done', () async {
    final c = _container(feedRepo: _OneFeedRepo());
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);
    await notifier.start(1, Uri.parse('http://x.com'));

    final ready = c.read(folderDownloadProvider) as FolderJobTreeReady;
    await notifier.confirmDownload(ready.checkedBooks);

    expect(c.read(folderDownloadProvider), isA<FolderJobDone>());
  });

  test('confirmDownload no-op when state is not FolderJobTreeReady', () async {
    final c = _container();
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);
    // State is idle — confirmDownload should do nothing
    await notifier.confirmDownload({});
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });

  test('cancel() during scan: FolderJobDone with wasCancelled = true', () async {
    final slowRepo = _SlowFeedRepo();
    final c = _container(feedRepo: slowRepo);
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);

    final startFuture = notifier.start(1, Uri.parse('http://x.com'));
    notifier.cancel();
    slowRepo.complete();
    await startFuture;

    final done = c.read(folderDownloadProvider) as FolderJobDone;
    expect(done.wasCancelled, isTrue);
  });

  test('reset() during FolderJobTreeReady returns to FolderJobIdle', () async {
    final c = _container(feedRepo: _OneFeedRepo());
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);
    await notifier.start(1, Uri.parse('http://x.com'));

    expect(c.read(folderDownloadProvider), isA<FolderJobTreeReady>());
    notifier.reset();
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });

  test('start() allowed again after reset()', () async {
    final c = _container(feedRepo: _OneFeedRepo());
    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);

    await notifier.start(1, Uri.parse('http://x.com'));
    expect(c.read(folderDownloadProvider), isA<FolderJobTreeReady>());

    notifier.reset();
    await notifier.start(1, Uri.parse('http://x.com'));
    expect(c.read(folderDownloadProvider), isA<FolderJobTreeReady>());
  });
}
```

- [ ] **Step 2: Run tests — confirm failures**

```powershell
flutter test test/ui/folder_download_notifier_test.dart
```
Expected: failures for `updateSelection`, `confirmDownload`, `reset` (not defined yet). `dismiss` calls break compilation.

- [ ] **Step 3: Rewrite `FolderDownloadNotifier` in `lib/ui/providers.dart`**

Replace the entire `// ── Folder download` section:

```dart
// ── Folder download ───────────────────────────────────────────────────────────

class FolderDownloadNotifier extends Notifier<FolderJobState> {
  FolderDownloadJob? _job;
  int _jobGen = 0;

  @override
  FolderJobState build() {
    ref.watch(bookDownloaderProvider); // warm up settings so first start() sees non-null
    return const FolderJobIdle();
  }

  Future<void> start(int catalogId, Uri url) async {
    if (state is! FolderJobIdle && state is! FolderJobDone) return;
    state = const FolderJobScanning(foldersFound: 0);

    final downloader = ref.read(bookDownloaderProvider);
    if (downloader == null) {
      state = FolderJobDone(
        root: DownloadFolder(title: '', children: []),
        results: const {},
        wasCancelled: true,
        stoppedAtLimit: false,
      );
      return;
    }

    final gen = ++_jobGen;
    _job = FolderDownloadJob(
      feedRepository: ref.read(feedRepositoryProvider),
      downloadFn: downloader.download,
      settings: ref.read(settingsProvider).requireValue,
      onProgress: (s) {
        if (_jobGen == gen) state = s;
      },
    );

    await _job!.run(catalogId, url);
    // _job kept alive for confirmDownload()
  }

  Future<void> confirmDownload(Set<Uri> checkedBooks) async {
    if (state is! FolderJobTreeReady) return;
    await _job!.download(checkedBooks);
    _job = null;
  }

  void updateSelection(Set<Uri> checkedBooks) {
    if (state is FolderJobTreeReady) {
      state = (state as FolderJobTreeReady).copyWith(checkedBooks: checkedBooks);
    }
  }

  /// Cancel in-flight job and return to idle.
  /// Called when user navigates back from FolderTreeScreen without completing.
  void reset() {
    ++_jobGen; // invalidate any pending onProgress callbacks
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

Remove the old `dismiss()` method. Remove the now-unused import of `folder_download_job.dart`'s old state fields if the analyzer flags anything.

- [ ] **Step 4: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/folder_download_notifier_test.dart
git commit -m "feat: update FolderDownloadNotifier — confirmDownload, updateSelection, reset, gen counter"
```

---

### Task 6: `FolderScanScreen` and new routes

**Files:**
- Create: `lib/ui/folder_scan_screen.dart`
- Modify: `lib/app.dart` (add two routes)
- Test: `test/ui/folder_scan_screen_test.dart` (create)

**Interfaces:**
- Produces: `FolderScanScreen` widget pushed from BrowseScreen; auto-navigates to `/folder-tree` on `FolderJobTreeReady`; pops on `FolderJobDone` (empty scan / cancel).
- Route `/folder-scan`: query params `catalogId` (int) and `url` (encoded Uri string).
- Route `/folder-tree`: no params (state lives in global notifier).

- [ ] **Step 1: Write failing widget test**

Create `test/ui/folder_scan_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/folder_scan_screen.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fake notifier ─────────────────────────────────────────────────────────────

class _FakeScanNotifier extends FolderDownloadNotifier {
  @override
  FolderJobState build() => const FolderJobScanning(foldersFound: 0);

  @override
  Future<void> start(int catalogId, Uri url) async {} // no-op in tests
}

// ── Router helper ─────────────────────────────────────────────────────────────

GoRouter _makeRouter(FolderJobState initialState) {
  return GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const SizedBox(),
    ),
    GoRoute(
      path: '/folder-scan',
      builder: (_, state) {
        return const FolderScanScreen(catalogId: 1, url: 'http://x.com/root');
      },
    ),
    GoRoute(
      path: '/folder-tree',
      builder: (_, __) => const Text('TreeScreen'),
    ),
  ], initialLocation: '/folder-scan');
}

Widget _wrap(FolderJobState state) {
  return ProviderScope(
    overrides: [
      folderDownloadProvider.overrideWith(() => _FakeScanNotifier()..state = state),
    ],
    child: MaterialApp.router(routerConfig: _makeRouter(state)),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows scanning text and folder count', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobScanning(foldersFound: 7)));
    expect(find.textContaining('7'), findsOneWidget);
    expect(find.textContaining('Scanning'), findsOneWidget);
  });

  testWidgets('shows Cancel button', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobScanning(foldersFound: 0)));
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('navigates to /folder-tree when state becomes FolderJobTreeReady', (tester) async {
    final book = DownloadBook(
      entry: BookEntry(title: 'B', authors: const ['A'], acquisitionLinks: [
        AcquisitionLink(
            url: Uri.parse('http://x.com/b.epub'),
            mimeType: 'application/epub+zip',
            formatLabel: 'EPUB'),
      ]),
      link: AcquisitionLink(
          url: Uri.parse('http://x.com/b.epub'),
          mimeType: 'application/epub+zip',
          formatLabel: 'EPUB'),
    );

    // Start scanning, then provider emits TreeReady
    final container = ProviderContainer(overrides: [
      folderDownloadProvider.overrideWith(() => _FakeScanNotifier()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _makeRouter(const FolderJobScanning(foldersFound: 0))),
      ),
    );

    // Simulate state change to TreeReady
    container.read(folderDownloadProvider.notifier).state =
        FolderJobTreeReady(root: book, checkedBooks: {Uri.parse('http://x.com/b.epub')});
    await tester.pumpAndSettle();

    expect(find.text('TreeScreen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test — confirm compile failure**

```powershell
flutter test test/ui/folder_scan_screen_test.dart
```
Expected: `FolderScanScreen` not found.

- [ ] **Step 3: Create `lib/ui/folder_scan_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';

class FolderScanScreen extends ConsumerStatefulWidget {
  const FolderScanScreen({
    required this.catalogId,
    required this.url,
    super.key,
  });
  final int catalogId;
  final String url;

  @override
  ConsumerState<FolderScanScreen> createState() => _FolderScanScreenState();
}

class _FolderScanScreenState extends ConsumerState<FolderScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(folderDownloadProvider.notifier)
          .start(widget.catalogId, Uri.parse(widget.url));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<FolderJobState>(folderDownloadProvider, (_, next) {
      if (!mounted) return;
      if (next is FolderJobTreeReady) {
        context.replace('/folder-tree');
      } else if (next is FolderJobDone) {
        context.pop();
      }
    });

    final state = ref.watch(folderDownloadProvider);
    final foldersFound =
        state is FolderJobScanning ? state.foldersFound : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Scanning folder')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Scanning… ($foldersFound folders found)'),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                ref.read(folderDownloadProvider.notifier).cancel();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add routes in `lib/app.dart`**

Add two new `GoRoute` entries to `_router`:

```dart
import 'package:opds_browser/ui/folder_scan_screen.dart';
import 'package:opds_browser/ui/folder_tree_screen.dart'; // created in Task 7

// Inside GoRouter routes list, after '/browse':
GoRoute(
  path: '/folder-scan',
  builder: (context, state) {
    final params = state.uri.queryParameters;
    return FolderScanScreen(
      catalogId: int.parse(params['catalogId']!),
      url: params['url']!,
    );
  },
),
GoRoute(
  path: '/folder-tree',
  builder: (context, state) => const FolderTreeScreen(),
),
```

Note: `FolderTreeScreen` import will cause a compile error until Task 7. Add the route now but create a placeholder class:

```dart
// Temporary placeholder at bottom of folder_scan_screen.dart until Task 7:
// Remove this once folder_tree_screen.dart exists.
```

Or create a minimal `lib/ui/folder_tree_screen.dart` stub now:

```dart
import 'package:flutter/material.dart';

class FolderTreeScreen extends StatelessWidget {
  const FolderTreeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Placeholder());
}
```

- [ ] **Step 5: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/folder_scan_screen.dart lib/ui/folder_tree_screen.dart lib/app.dart test/ui/folder_scan_screen_test.dart
git commit -m "feat: add FolderScanScreen and go_router routes for folder-scan and folder-tree"
```

---

### Task 7: `FolderTreeScreen` — selection mode

**Files:**
- Modify (replace stub): `lib/ui/folder_tree_screen.dart`
- Test: `test/ui/folder_tree_screen_test.dart` (create — selection mode tests)

**Interfaces:**
- Consumes: `FolderJobTreeReady(root, checkedBooks, stoppedAtLimit)`.
- Calls: `notifier.updateSelection(Set<Uri>)`, `notifier.confirmDownload(Set<Uri>)`, `notifier.reset()`.

- [ ] **Step 1: Write failing widget tests (selection mode)**

Create `test/ui/folder_tree_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/folder_tree_screen.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AcquisitionLink _link(String id) => AcquisitionLink(
      url: Uri.parse('http://x.com/$id.epub'),
      mimeType: 'application/epub+zip',
      formatLabel: 'EPUB',
    );

DownloadBook _book(String id) => DownloadBook(
      entry: BookEntry(title: 'Book $id', authors: const ['A'], acquisitionLinks: [_link(id)]),
      link: _link(id),
    );

DownloadFolder _folder(String title, List<DownloadTreeNode> children) =>
    DownloadFolder(title: title, children: children);

class _FakeTreeNotifier extends FolderDownloadNotifier {
  Set<Uri>? lastSelection;
  Set<Uri>? lastConfirm;
  bool resetCalled = false;

  @override
  FolderJobState build() => const FolderJobIdle();

  @override
  void updateSelection(Set<Uri> checkedBooks) {
    lastSelection = checkedBooks;
    state = (state as FolderJobTreeReady).copyWith(checkedBooks: checkedBooks);
  }

  @override
  Future<void> confirmDownload(Set<Uri> checkedBooks) async {
    lastConfirm = checkedBooks;
  }

  @override
  void reset() { resetCalled = true; }
}

Widget _wrapWithState(FolderJobState initialState) {
  final notifier = _FakeTreeNotifier()..state = initialState;
  return ProviderScope(
    overrides: [
      folderDownloadProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const FolderTreeScreen()),
      ]),
    ),
  );
}

// ── Selection mode tests ───────────────────────────────────────────────────────

void main() {
  group('selection mode', () {
    testWidgets('shows book title and checkbox', (tester) async {
      final book = _book('1');
      final state = FolderJobTreeReady(
        root: book,
        checkedBooks: {book.link.url},
      );
      await tester.pumpWidget(_wrapWithState(state));
      expect(find.text('Book 1'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('shows folder title with tri-state checkbox', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final folder = _folder('MyFolder', [b1, b2]);
      final state = FolderJobTreeReady(
        root: folder,
        checkedBooks: {b1.link.url, b2.link.url},
      );
      await tester.pumpWidget(_wrapWithState(state));
      expect(find.text('MyFolder'), findsOneWidget);
      // 3 checkboxes: folder + 2 books
      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('Download button shows book count', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final state = FolderJobTreeReady(
        root: _folder('F', [b1, b2]),
        checkedBooks: {b1.link.url, b2.link.url},
      );
      await tester.pumpWidget(_wrapWithState(state));
      expect(find.textContaining('2'), findsWidgets);
      expect(find.textContaining('Download'), findsOneWidget);
    });

    testWidgets('Download button disabled when no books checked', (tester) async {
      final b1 = _book('1');
      final state = FolderJobTreeReady(
        root: b1,
        checkedBooks: const {},
      );
      await tester.pumpWidget(_wrapWithState(state));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('tapping book checkbox calls updateSelection', (tester) async {
      final b1 = _book('1');
      final notifier = _FakeTreeNotifier()
        ..state = FolderJobTreeReady(root: b1, checkedBooks: {b1.link.url});
      await tester.pumpWidget(ProviderScope(
        overrides: [folderDownloadProvider.overrideWith(() => notifier)],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const FolderTreeScreen()),
          ]),
        ),
      ));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(notifier.lastSelection, isNotNull);
    });

    testWidgets('tapping folder checkbox unchecks all children', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final folder = _folder('F', [b1, b2]);
      final notifier = _FakeTreeNotifier()
        ..state = FolderJobTreeReady(
            root: folder, checkedBooks: {b1.link.url, b2.link.url});
      await tester.pumpWidget(ProviderScope(
        overrides: [folderDownloadProvider.overrideWith(() => notifier)],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const FolderTreeScreen()),
          ]),
        ),
      ));
      // First checkbox is the folder
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(notifier.lastSelection, isEmpty);
    });

    testWidgets('tapping Download button calls confirmDownload', (tester) async {
      final b1 = _book('1');
      final notifier = _FakeTreeNotifier()
        ..state = FolderJobTreeReady(root: b1, checkedBooks: {b1.link.url});
      await tester.pumpWidget(ProviderScope(
        overrides: [folderDownloadProvider.overrideWith(() => notifier)],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const FolderTreeScreen()),
          ]),
        ),
      ));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(notifier.lastConfirm, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run tests — confirm failures**

```powershell
flutter test test/ui/folder_tree_screen_test.dart
```
Expected: failures (stub `FolderTreeScreen` shows `Placeholder`).

- [ ] **Step 3: Implement selection mode in `lib/ui/folder_tree_screen.dart`**

Replace the placeholder stub entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';

class FolderTreeScreen extends ConsumerWidget {
  const FolderTreeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(folderDownloadProvider);
    return switch (state) {
      FolderJobTreeReady() => _SelectionView(state: state),
      FolderJobDownloading() => _DownloadView(state: state),   // Task 8
      FolderJobDone() => _DoneView(state: state),              // Task 8
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

// ── Selection view ─────────────────────────────────────────────────────────────

class _SelectionView extends ConsumerWidget {
  const _SelectionView({required this.state});
  final FolderJobTreeReady state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(folderDownloadProvider.notifier);
    final rows = _flattenTree(state.root, 0);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) notifier.reset();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Select books')),
        body: Column(
          children: [
            if (state.stoppedAtLimit)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Large catalogue — some content may not be shown (limit reached).',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final (node, depth) = rows[i];
                  return _TreeRow(
                    node: node,
                    depth: depth,
                    checkedBooks: state.checkedBooks,
                    onChanged: (newChecked) => notifier.updateSelection(newChecked),
                    subtreeBooks: _collectBookUrls(node),
                  );
                },
              ),
            ),
            _SelectionBottomBar(checkedBooks: state.checkedBooks, notifier: notifier),
          ],
        ),
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.checkedBooks,
    required this.onChanged,
    required this.subtreeBooks,
  });
  final DownloadTreeNode node;
  final int depth;
  final Set<Uri> checkedBooks;
  final void Function(Set<Uri>) onChanged;
  final Set<Uri> subtreeBooks;

  @override
  Widget build(BuildContext context) {
    final indent = depth * 16.0;
    if (node is DownloadBook) {
      final book = node as DownloadBook;
      final isChecked = checkedBooks.contains(book.link.url);
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: CheckboxListTile(
          value: isChecked,
          title: Text(book.entry.title),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (_) {
            final updated = Set<Uri>.from(checkedBooks);
            if (isChecked) {
              updated.remove(book.link.url);
            } else {
              updated.add(book.link.url);
            }
            onChanged(updated);
          },
        ),
      );
    } else {
      final folder = node as DownloadFolder;
      final checkedInFolder = subtreeBooks.intersection(checkedBooks).length;
      final triState = checkedInFolder == 0
          ? false
          : checkedInFolder == subtreeBooks.length
              ? true
              : null; // indeterminate
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: CheckboxListTile(
          value: triState,
          tristate: true,
          title: Text(folder.title),
          leading: const Icon(Icons.folder),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (_) {
            final updated = Set<Uri>.from(checkedBooks);
            if (triState == true || triState == null) {
              // checked or indeterminate → uncheck all
              updated.removeAll(subtreeBooks);
            } else {
              // unchecked → check all
              updated.addAll(subtreeBooks);
            }
            onChanged(updated);
          },
        ),
      );
    }
  }
}

class _SelectionBottomBar extends StatelessWidget {
  const _SelectionBottomBar({
    required this.checkedBooks,
    required this.notifier,
  });
  final Set<Uri> checkedBooks;
  final FolderDownloadNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: checkedBooks.isEmpty
              ? null
              : () => notifier.confirmDownload(checkedBooks),
          child: Text('Download (${checkedBooks.length} books)'),
        ),
      ),
    );
  }
}

// Placeholder views for download/done modes — replaced in Task 8
class _DownloadView extends StatelessWidget {
  const _DownloadView({required this.state});
  final FolderJobDownloading state;
  @override
  Widget build(BuildContext context) => const Scaffold(body: Placeholder());
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.state});
  final FolderJobDone state;
  @override
  Widget build(BuildContext context) => const Scaffold(body: Placeholder());
}

// ── Tree utilities ─────────────────────────────────────────────────────────────

List<(DownloadTreeNode, int)> _flattenTree(DownloadTreeNode node, int depth) {
  if (node is DownloadBook) return [(node, depth)];
  final folder = node as DownloadFolder;
  return [
    (folder, depth),
    ...folder.children.expand((c) => _flattenTree(c, depth + 1)),
  ];
}

Set<Uri> _collectBookUrls(DownloadTreeNode node) {
  if (node is DownloadBook) return {(node as DownloadBook).link.url};
  return (node as DownloadFolder)
      .children
      .fold(<Uri>{}, (acc, c) => acc..addAll(_collectBookUrls(c)));
}
```

- [ ] **Step 4: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/folder_tree_screen.dart test/ui/folder_tree_screen_test.dart
git commit -m "feat: implement FolderTreeScreen selection mode with tri-state folder checkboxes"
```

---

### Task 8: `FolderTreeScreen` — download and done modes

Replace the `_DownloadView` and `_DoneView` stubs with full implementations including per-book status icons, progress bar, error popup, and Close button.

**Files:**
- Modify: `lib/ui/folder_tree_screen.dart`
- Test: `test/ui/folder_tree_screen_test.dart` (add download/done groups)

- [ ] **Step 1: Write failing tests for download and done modes**

Append to `test/ui/folder_tree_screen_test.dart`:

```dart
  group('download mode', () {
    DownloadBook _bookWithLink(String id) => _book(id);

    FolderJobDownloading _downloadState({
      required DownloadTreeNode root,
      Uri? currentBook,
      Map<Uri, BookDownloadResult> results = const {},
      int total = 1,
      int completedCount = 0,
    }) =>
        FolderJobDownloading(
          root: root,
          currentBook: currentBook,
          results: results,
          total: total,
          completedCount: completedCount,
        );

    testWidgets('current book shows CircularProgressIndicator', (tester) async {
      final b = _bookWithLink('1');
      await tester.pumpWidget(_wrapWithState(
        _downloadState(root: b, currentBook: b.link.url, total: 1),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('done book shows green check icon', (tester) async {
      final b = _bookWithLink('1');
      await tester.pumpWidget(_wrapWithState(
        _downloadState(
          root: b,
          results: {b.link.url: const BookDownloadResult(status: BookDownloadStatus.done)},
          total: 1,
          completedCount: 1,
        ),
      ));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('failed book shows red warning icon', (tester) async {
      final b = _bookWithLink('1');
      await tester.pumpWidget(_wrapWithState(
        _downloadState(
          root: b,
          results: {
            b.link.url: const BookDownloadResult(
                status: BookDownloadStatus.failed, error: 'timeout')
          },
          total: 1,
          completedCount: 1,
        ),
      ));
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    });

    testWidgets('tapping warning icon shows error dialog', (tester) async {
      final b = _bookWithLink('1');
      await tester.pumpWidget(_wrapWithState(
        _downloadState(
          root: b,
          results: {
            b.link.url: const BookDownloadResult(
                status: BookDownloadStatus.failed, error: 'network error')
          },
          total: 1,
          completedCount: 1,
        ),
      ));
      await tester.tap(find.byIcon(Icons.warning_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('network error'), findsOneWidget);
    });

    testWidgets('shows LinearProgressIndicator and Cancel button', (tester) async {
      final b = _bookWithLink('1');
      await tester.pumpWidget(_wrapWithState(
        _downloadState(root: b, total: 3, completedCount: 1),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('checkboxes are hidden in download mode', (tester) async {
      final b = _bookWithLink('1');
      await tester.pumpWidget(_wrapWithState(
        _downloadState(root: b, total: 1),
      ));
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('done mode', () {
    testWidgets('shows Close button', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(FolderJobDone(
        root: b,
        results: {b.link.url: const BookDownloadResult(status: BookDownloadStatus.done)},
        wasCancelled: false,
        stoppedAtLimit: false,
      )));
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('wasCancelled shows cancellation notice', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(FolderJobDone(
        root: b,
        results: {},
        wasCancelled: true,
        stoppedAtLimit: false,
      )));
      expect(find.textContaining('cancelled'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run tests — confirm failures**

```powershell
flutter test test/ui/folder_tree_screen_test.dart
```
Expected: download/done mode tests fail (stubs show `Placeholder`).

- [ ] **Step 3: Replace `_DownloadView` and `_DoneView` stubs in `lib/ui/folder_tree_screen.dart`**

Replace the two placeholder classes:

```dart
// ── Download view ─────────────────────────────────────────────────────────────

class _DownloadView extends ConsumerWidget {
  const _DownloadView({required this.state});
  final FolderJobDownloading state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(folderDownloadProvider.notifier);
    final rows = _flattenTree(state.root, 0);
    final progress = state.total > 0 ? state.completedCount / state.total : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Downloading')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final (node, depth) = rows[i];
                if (node is! DownloadBook) {
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text((node as DownloadFolder).title),
                    ),
                  );
                }
                final book = node as DownloadBook;
                final result = state.results[book.link.url];
                final isCurrent = state.currentBook == book.link.url;
                final icon = _bookIcon(book.link.url, isCurrent, result, context);
                return Padding(
                  padding: EdgeInsets.only(left: depth * 16.0),
                  child: ListTile(
                    leading: icon,
                    title: Text(book.entry.title),
                  ),
                );
              },
            ),
          ),
          _DownloadBottomBar(
            progress: progress,
            onCancel: notifier.cancel,
          ),
        ],
      ),
    );
  }
}

class _DoneView extends ConsumerWidget {
  const _DoneView({required this.state});
  final FolderJobDone state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = _flattenTree(state.root, 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Download complete')),
      body: Column(
        children: [
          if (state.wasCancelled)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Download was cancelled.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          if (state.stoppedAtLimit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Catalogue limit reached — not all books were scanned.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final (node, depth) = rows[i];
                if (node is! DownloadBook) {
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text((node as DownloadFolder).title),
                    ),
                  );
                }
                final book = node as DownloadBook;
                final result = state.results[book.link.url];
                final icon = _bookIcon(book.link.url, false, result, context);
                return Padding(
                  padding: EdgeInsets.only(left: depth * 16.0),
                  child: ListTile(
                    leading: icon,
                    title: Text(book.entry.title),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared book status icon ───────────────────────────────────────────────────

Widget _bookIcon(Uri linkUrl, bool isCurrent, BookDownloadResult? result, BuildContext context) {
  if (isCurrent) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
  if (result == null) {
    return const Icon(Icons.schedule, color: Colors.grey);
  }
  return switch (result.status) {
    BookDownloadStatus.done || BookDownloadStatus.skipped =>
      const Icon(Icons.check_circle, color: Colors.green),
    BookDownloadStatus.failed => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Download failed'),
            content: Text(result.error ?? 'Unknown error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
        child: const Icon(Icons.warning_rounded, color: Colors.red),
      ),
    BookDownloadStatus.downloading => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
  };
}

// ── Download bottom bar ───────────────────────────────────────────────────────

class _DownloadBottomBar extends StatelessWidget {
  const _DownloadBottomBar({required this.progress, required this.onCancel});
  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: progress)),
            const SizedBox(width: 16),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/folder_tree_screen.dart test/ui/folder_tree_screen_test.dart
git commit -m "feat: implement FolderTreeScreen download and done modes with per-book status icons"
```

---

### Task 9: Wire BrowseScreen and delete `FolderJobBanner`

Update `BrowseScreen` to navigate to the scan screen instead of starting a job inline. Delete the banner widget and its stub. Update existing browse screen tests.

**Files:**
- Modify: `lib/ui/browse_screen.dart`
- Delete: `lib/ui/widgets/folder_job_banner.dart`
- Modify: `test/ui/browse_screen_test.dart`

- [ ] **Step 1: Check existing browse_screen_test.dart for banner references**

```powershell
Select-String -Path "test/ui/browse_screen_test.dart" -Pattern "FolderJob|banner|dismiss|scanning" -CaseSensitive:$false | Select-Object LineNumber, Line
```

Remove any tests that reference `FolderJobBanner`, `FolderJobScanning`, `FolderJobDownloading`, `FolderJobDone` in the context of the banner. These tests are replaced by the scan/tree screen tests.

- [ ] **Step 2: Update `lib/ui/browse_screen.dart`**

**Remove** the `FolderJobBanner` import and usage:
- Remove: `import 'package:opds_browser/ui/widgets/folder_job_banner.dart';`
- Remove: `const FolderJobBanner(),` from the body `Column`

**Update** the AppBar download button:
```dart
// Replace the existing folder download IconButton with:
IconButton(
  icon: const Icon(Icons.download_for_offline_outlined),
  tooltip: 'Download folder',
  onPressed: jobState is FolderJobIdle
      ? () => context.push(
            '/folder-scan?catalogId=$catalogId&url=${Uri.encodeComponent(url.toString())}',
          )
      : null,
),
```

The guard is now `jobState is FolderJobIdle` only (no dialog — the scan screen is the entry point). Remove the old `showDialog` call entirely.

- [ ] **Step 3: Delete banner widget**

```powershell
Remove-Item "lib/ui/widgets/folder_job_banner.dart"
```

Check if `lib/ui/widgets/` is now empty; if so, remove the directory too:

```powershell
if ((Get-ChildItem "lib/ui/widgets/").Count -eq 0) { Remove-Item "lib/ui/widgets/" }
```

- [ ] **Step 4: Run check**

```powershell
dart run tool/check.dart
```
Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/browse_screen.dart test/ui/browse_screen_test.dart
git rm lib/ui/widgets/folder_job_banner.dart
git commit -m "feat: wire BrowseScreen to FolderScanScreen; remove FolderJobBanner"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Parser builds full tree of folders and books | Task 3 |
| Single-book folders collapsed to book | Task 3 (`_collapseTree`) |
| Empty folders pruned | Task 3 (`_collapseTreeNullable`) |
| Tree screen with checkboxes, all checked by default | Task 7 |
| Folder tri-state checkboxes | Task 7 |
| Download button sticky at bottom | Task 7 |
| Only checked books downloaded | Task 4 (`download()` filters by `checkedBooks`) |
| 5-second pause between books | Task 4 (`Future.delayed(_downloadDelay)`) |
| Scan progress screen | Task 6 |
| Auto-navigate to tree on scan complete | Task 6 |
| Download progress on same screen | Task 8 |
| Book spinner / green check / red warning icons | Task 8 |
| Error popup on tap | Task 8 |
| Progress bar + red Cancel during download | Task 8 |
| Close button in done state | Task 8 |
| Back button in selection mode calls reset() | Task 7 (`PopScope`) |
| FolderJobBanner deleted | Task 9 |
| BrowseScreen button → navigate to scan screen | Task 9 |
| Generation counter prevents stale progress | Task 5 |
| Safety limits preserved | Task 3 |

**No placeholders found.** All code blocks are complete.

**Type consistency verified:** `DownloadBook`, `DownloadFolder`, `BookDownloadResult`, `BookDownloadStatus` defined in Task 1 and used consistently. `FolderJobTreeReady.copyWith` defined in Task 2 and used in Task 5. `_flattenTree`, `_collectBookUrls` defined once in `folder_tree_screen.dart` (Task 7) and reused in Task 8. `_filterTree`, `_collectTasks`, `_collapseTree` defined in `folder_download_job.dart` (Task 3) and used in Task 4.

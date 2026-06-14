# Folder Download Job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement folder download (BFS traversal + background download with concurrency 2), a global persistent progress banner on every BrowseScreen, and a dismiss button on the single-book download snackbar.

**Architecture:** `FolderDownloadJob` (data layer, pure Dart) drives BFS + downloads via a `DownloadFn` callback. A global non-autoDispose `FolderDownloadNotifier` in `providers.dart` holds `FolderJobState`. Every `BrowseScreen` reads this provider and renders a `FolderJobBanner` at the bottom of its body column.

**Tech Stack:** Flutter, Riverpod 2.x (no codegen), `dart:collection.Queue`, existing `FeedRepository`, `BookDownloader`, `normalizeUrl`, `folderPreferredLink` (new).

---

## File Map

| File | Action |
|------|--------|
| `lib/data/folder_download_job.dart` | **Create** — `FolderJobState` sealed class + `FolderDownloadJob` |
| `lib/domain/download_utils.dart` | **Modify** — add `folderPreferredLink` |
| `lib/ui/providers.dart` | **Modify** — add `FolderDownloadNotifier`, `folderDownloadProvider` |
| `lib/ui/widgets/folder_job_banner.dart` | **Create** — progress/summary banner widget |
| `lib/ui/browse_screen.dart` | **Modify** — wire Download-folder button, embed banner, add `showCloseIcon` |
| `test/data/folder_download_job_test.dart` | **Create** |
| `test/domain/download_utils_test.dart` | **Modify** — add `folderPreferredLink` group |
| `test/ui/folder_download_notifier_test.dart` | **Create** |
| `test/ui/folder_job_banner_test.dart` | **Create** |
| `test/ui/browse_screen_test.dart` | **Modify** — add folder-job banner tests |

---

### Task 1: FolderJobState sealed class + FolderDownloadJob skeleton

**Files:**
- Create: `lib/data/folder_download_job.dart`

No tests for pure data types. This task just lays down the types used by every later task.

- [ ] **Step 1: Create `lib/data/folder_download_job.dart`**

```dart
import 'dart:collection';

import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';

/// Function type used by [FolderDownloadJob] to download a single book.
/// Matches [BookDownloader.download] so the real implementation can be passed
/// directly as a method reference.
typedef DownloadFn = Future<String> Function(
    BookEntry entry, AcquisitionLink link, AppSettings settings);

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

// ── Job ───────────────────────────────────────────────────────────────────────

class FolderDownloadJob {
  FolderDownloadJob({
    required FeedRepository feedRepository,
    required DownloadFn download,
    required AppSettings settings,
    required void Function(FolderJobState) onProgress,
  })  : _feedRepository = feedRepository,
        _download = download,
        _settings = settings,
        _onProgress = onProgress;

  final FeedRepository _feedRepository;
  final DownloadFn _download;
  final AppSettings _settings;
  final void Function(FolderJobState) _onProgress;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  Future<void> run(int catalogId, Uri startUrl) async {
    // TODO: implement in Tasks 3 and 4
  }
}
```

- [ ] **Step 2: Verify it compiles**

```powershell
flutter analyze lib/data/folder_download_job.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```powershell
git add lib/data/folder_download_job.dart
git commit -m "feat(data): add FolderJobState + FolderDownloadJob skeleton"
```

---

### Task 2: `folderPreferredLink` — TDD

**Files:**
- Modify: `test/domain/download_utils_test.dart`
- Modify: `lib/domain/download_utils.dart`

- [ ] **Step 1: Add failing tests to `test/domain/download_utils_test.dart`**

Add this group at the end of `main()`, after the existing `buildPathSegments` group:

```dart
  // ── folderPreferredLink ───────────────────────────────────────────────────

  group('folderPreferredLink', () {
    test('single link returned directly', () {
      final link = _link('EPUB');
      expect(folderPreferredLink([link]), same(link));
    });

    test('FB2.ZIP preferred over EPUB when present', () {
      final fb2zip = _link('FB2.ZIP');
      final epub = _link('EPUB');
      expect(folderPreferredLink([epub, fb2zip]), same(fb2zip));
    });

    test('no FB2 variants — EPUB preferred over PDF', () {
      final epub = _link('EPUB');
      final pdf = _link('PDF');
      expect(folderPreferredLink([pdf, epub]), same(epub));
    });

    test('no FB2, no EPUB — PDF preferred over MOBI', () {
      final pdf = _link('PDF');
      final mobi = _link('MOBI');
      expect(folderPreferredLink([mobi, pdf]), same(pdf));
    });

    test('no FB2, no EPUB, no PDF — MOBI returned', () {
      final mobi = _link('MOBI');
      final djvu = _link('DJVU');
      expect(folderPreferredLink([djvu, mobi]), same(mobi));
    });

    test('no priority match — first link returned', () {
      final first = _link('DJVU');
      final second = _link('AZW3');
      expect(folderPreferredLink([first, second]), same(first));
    });
  });
```

Also add the import at the top of the test file (it already imports `download_utils.dart`, so `folderPreferredLink` will be available once implemented).

- [ ] **Step 2: Run to confirm failure**

```powershell
flutter test test/domain/download_utils_test.dart
```

Expected: compile error — `folderPreferredLink` not defined.

- [ ] **Step 3: Implement `folderPreferredLink` in `lib/domain/download_utils.dart`**

Add after the `buildPathSegments` function:

```dart
/// Selects the best [AcquisitionLink] for an automated folder download.
/// Unlike [preferredLink], never returns null — falls back to EPUB > PDF >
/// MOBI > first listed when no FB2 variant is present.
AcquisitionLink folderPreferredLink(List<AcquisitionLink> links) {
  final preferred = preferredLink(links);
  if (preferred != null) return preferred;
  const priority = ['EPUB', 'PDF', 'MOBI'];
  for (final label in priority) {
    final m = links.where((l) => l.formatLabel == label).firstOrNull;
    if (m != null) return m;
  }
  return links.first;
}
```

- [ ] **Step 4: Run tests**

```powershell
flutter test test/domain/download_utils_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/domain/download_utils.dart test/domain/download_utils_test.dart
git commit -m "feat(domain): add folderPreferredLink"
```

---

### Task 3: `FolderDownloadJob` — BFS scanning phase TDD

**Files:**
- Create: `test/data/folder_download_job_test.dart`
- Modify: `lib/data/folder_download_job.dart`

- [ ] **Step 1: Create `test/data/folder_download_job_test.dart` with fakes and BFS tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeFeedRepository implements FeedRepository {
  final _feeds = <String, List<FeedEntry>>{};
  final _errors = <String, Exception>{};
  int callCount = 0;

  void addFeed(Uri url, List<FeedEntry> entries) =>
      _feeds[url.toString()] = entries;

  void addError(Uri url, Exception e) => _errors[url.toString()] = e;

  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
      {bool forceRefresh = false}) async {
    callCount++;
    final key = url.toString();
    if (_errors.containsKey(key)) throw _errors[key]!;
    return CachedFeed(
      feed: ParsedFeed(title: 'Feed', entries: _feeds[key] ?? []),
      fetchedAt: DateTime.now(),
      fromCache: false,
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

const _settings = AppSettings(target: SystemDownloads());

NavigationEntry _nav(String path) => NavigationEntry(
      title: 'Nav',
      url: Uri.parse('http://example.com$path'),
    );

BookEntry _book(String id) => BookEntry(
      title: 'Book $id',
      authors: const ['Author'],
      acquisitionLinks: [
        AcquisitionLink(
          url: Uri.parse('http://example.com/books/$id.epub'),
          mimeType: 'application/epub+zip',
          formatLabel: 'EPUB',
        ),
      ],
    );

Future<String> _noOp(BookEntry e, AcquisitionLink l, AppSettings s) async =>
    'content://ok';

FolderDownloadJob _makeJob(
  _FakeFeedRepository repo, {
  DownloadFn? download,
  required List<FolderJobState> states,
}) =>
    FolderDownloadJob(
      feedRepository: repo,
      download: download ?? _noOp,
      settings: _settings,
      onProgress: states.add,
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('BFS scanning', () {
    test('visits root and follows navigation entries', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      final sub = Uri.parse('http://example.com/sub');
      repo.addFeed(root, [_nav('/sub')]);
      repo.addFeed(sub, [_book('1')]);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      final scanning = states.whereType<FolderJobScanning>().toList();
      expect(scanning.last.foldersFound, 2);
      final done = states.last as FolderJobDone;
      expect(done.downloaded, 1);
    });

    test('cycle protection — same URL visited once', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      // root links to itself AND a book
      repo.addFeed(root, [_nav('/root'), _book('1')]);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      expect(repo.callCount, 1); // only fetched once
      final done = states.last as FolderJobDone;
      expect(done.downloaded, 1);
    });

    test('inaccessible feed is silently skipped', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_nav('/bad'), _nav('/good')]);
      repo.addError(Uri.parse('http://example.com/bad'), Exception('timeout'));
      repo.addFeed(Uri.parse('http://example.com/good'), [_book('ok')]);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.downloaded, 1);
      expect(done.failed, 0); // feed error ≠ download failure
    });

    test('empty feed emits FolderJobDone with zeros', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, []);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.downloaded, 0);
      expect(done.stoppedAtLimit, false);
      expect(done.wasCancelled, false);
    });
  });

  group('safety limits', () {
    test('folders deeper than depth 10 are skipped, stoppedAtLimit = true',
        () async {
      final repo = _FakeFeedRepository();
      // Chain f0 (depth 0) → f1 → … → f10 → f11 (depth 11, should be skipped)
      for (var i = 0; i <= 10; i++) {
        repo.addFeed(
          Uri.parse('http://example.com/f$i'),
          [NavigationEntry(title: 'F', url: Uri.parse('http://example.com/f${i + 1}'))],
        );
      }
      // f11 has a book — should never be reached
      repo.addFeed(Uri.parse('http://example.com/f11'), [_book('deep')]);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states)
          .run(1, Uri.parse('http://example.com/f0'));

      final done = states.last as FolderJobDone;
      expect(done.stoppedAtLimit, isTrue);
      expect(done.downloaded, 0);
    });

    test('500th+ folder is skipped, stoppedAtLimit = true', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      // 500 sub-folders: root visits first 499, the 500th triggers limit
      final subs = List.generate(
        500,
        (i) => NavigationEntry(
            title: 'F$i', url: Uri.parse('http://example.com/sub/$i')),
      );
      repo.addFeed(root, subs);
      for (var i = 0; i < 500; i++) {
        repo.addFeed(Uri.parse('http://example.com/sub/$i'), []);
      }

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      expect((states.last as FolderJobDone).stoppedAtLimit, isTrue);
    });

    test('at most 2000 books collected, stoppedAtLimit = true', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, List.generate(2001, (i) => _book('$i')));

      var downloadCount = 0;
      final states = <FolderJobState>[];
      await _makeJob(repo,
        download: (e, l, s) async { downloadCount++; return 'content://ok'; },
        states: states,
      ).run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.stoppedAtLimit, isTrue);
      expect(done.downloaded, 2000);
      expect(downloadCount, 2000);
    });
  });

  group('cancellation', () {
    test('cancel during scan emits done with wasCancelled = true', () async {
      final repo = _CancellingFeedRepository(cancelAfterCalls: 2);
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_nav('/sub')]);
      repo.addFeed(Uri.parse('http://example.com/sub'), [_book('1')]);

      final states = <FolderJobState>[];
      final job = FolderDownloadJob(
        feedRepository: repo,
        download: _noOp,
        settings: _settings,
        onProgress: states.add,
      );
      repo.job = job;
      await job.run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.wasCancelled, isTrue);
    });

    test('cancel during download: workers exit, wasCancelled = true', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, List.generate(10, (i) => _book('$i')));

      var downloadCount = 0;
      FolderDownloadJob? job;
      final states = <FolderJobState>[];

      job = FolderDownloadJob(
        feedRepository: repo,
        download: (e, l, s) async {
          downloadCount++;
          if (downloadCount == 2) job!.cancel();
          return 'content://ok';
        },
        settings: _settings,
        onProgress: states.add,
      );
      await job.run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.wasCancelled, isTrue);
      expect(downloadCount, lessThan(10));
    });
  });
}

class _CancellingFeedRepository implements FeedRepository {
  _CancellingFeedRepository({required this.cancelAfterCalls});
  final int cancelAfterCalls;
  FolderDownloadJob? job;
  int _callCount = 0;
  final _feeds = <String, List<FeedEntry>>{};

  void addFeed(Uri url, List<FeedEntry> entries) =>
      _feeds[url.toString()] = entries;

  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
      {bool forceRefresh = false}) async {
    _callCount++;
    if (_callCount >= cancelAfterCalls) job?.cancel();
    return CachedFeed(
      feed: ParsedFeed(title: 'F', entries: _feeds[url.toString()] ?? []),
      fetchedAt: DateTime.now(),
      fromCache: false,
    );
  }
}
```

- [ ] **Step 2: Run to confirm failures**

```powershell
flutter test test/data/folder_download_job_test.dart
```

Expected: tests compile but all scanning/BFS tests fail (run() is empty).

- [ ] **Step 3: Implement BFS scanning phase in `lib/data/folder_download_job.dart`**

Replace the `run()` stub with:

```dart
  Future<void> run(int catalogId, Uri startUrl) async {
    // ── Phase 1: BFS scanning ─────────────────────────────────────────────
    final visited = <String>{};
    final queue = Queue<(Uri, int)>();
    final tasks = <(BookEntry, AcquisitionLink)>[];
    var stoppedAtLimit = false;
    var folderCount = 0;

    queue.add((startUrl, 0));

    while (queue.isNotEmpty && !_cancelled) {
      final (url, depth) = queue.removeFirst();
      final key = normalizeUrl(url);
      if (visited.contains(key)) continue;
      visited.add(key);

      if (depth > 10 || folderCount >= 500 || tasks.length >= 2000) {
        stoppedAtLimit = true;
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

      for (final entry in cached.feed.entries) {
        if (entry is NavigationEntry) {
          queue.add((entry.url, depth + 1));
        } else if (entry is BookEntry && tasks.length < 2000) {
          tasks.add((entry, folderPreferredLink(entry.acquisitionLinks)));
        }
      }
      if (tasks.length >= 2000) stoppedAtLimit = true;
    }

    if (_cancelled || tasks.isEmpty) {
      _onProgress(FolderJobDone(
        downloaded: 0,
        skipped: 0,
        failed: 0,
        stoppedAtLimit: stoppedAtLimit,
        wasCancelled: _cancelled,
      ));
      return;
    }

    // Phase 2 implemented in Task 4
    _onProgress(FolderJobDone(
      downloaded: 0,
      skipped: 0,
      failed: 0,
      stoppedAtLimit: stoppedAtLimit,
    ));
  }
```

- [ ] **Step 4: Run tests**

```powershell
flutter test test/data/folder_download_job_test.dart
```

Expected: all scanning and limit tests pass; download-count assertions (e.g. `done.downloaded, 1`) still fail because the download phase is not yet implemented.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/folder_download_job.dart test/data/folder_download_job_test.dart
git commit -m "feat(data): implement FolderDownloadJob BFS scanning phase"
```

---

### Task 4: `FolderDownloadJob` — download phase TDD

**Files:**
- Modify: `test/data/folder_download_job_test.dart` (add download tests)
- Modify: `lib/data/folder_download_job.dart` (complete `run()`)

- [ ] **Step 1: Add download tests to the test file**

Add a new `group('download phase', ...)` inside `main()`:

```dart
  group('download phase', () {
    test('successful download increments downloaded count', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_book('1'), _book('2')]);

      final states = <FolderJobState>[];
      await _makeJob(repo,
        download: (e, l, s) async => 'content://ok',
        states: states,
      ).run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.downloaded, 2);
      expect(done.skipped, 0);
      expect(done.failed, 0);
    });

    test('already_exists sentinel increments skipped count', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_book('1')]);

      final states = <FolderJobState>[];
      await _makeJob(repo,
        download: (e, l, s) async => 'already_exists',
        states: states,
      ).run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.skipped, 1);
      expect(done.downloaded, 0);
    });

    test('download exception increments failed count, job continues', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_book('bad'), _book('good')]);

      var calls = 0;
      final states = <FolderJobState>[];
      await _makeJob(repo,
        download: (e, l, s) async {
          calls++;
          if (e.title == 'Book bad') throw Exception('network error');
          return 'content://ok';
        },
        states: states,
      ).run(1, root);

      final done = states.last as FolderJobDone;
      expect(done.failed, 1);
      expect(done.downloaded, 1);
      expect(calls, 2); // both attempted
    });

    test('FolderJobDownloading progress emitted after each download', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_book('1'), _book('2'), _book('3')]);

      final states = <FolderJobState>[];
      await _makeJob(repo,
        download: (e, l, s) async => 'content://ok',
        states: states,
      ).run(1, root);

      final downloading = states.whereType<FolderJobDownloading>().toList();
      // At minimum: initial (0/3) + 3 updates (one per completed download)
      // With 2 workers some may arrive out of order but total should be 3
      expect(downloading.last.completed, 3);
      expect(downloading.last.total, 3);
    });
  });
```

- [ ] **Step 2: Run to confirm failures**

```powershell
flutter test test/data/folder_download_job_test.dart --name "download phase"
```

Expected: all download-phase tests fail (`downloaded` is always 0).

- [ ] **Step 3: Replace the Phase 2 placeholder in `run()` with the worker-pool implementation**

Replace the block starting with `// Phase 2 implemented in Task 4`:

```dart
    // ── Phase 2: download with concurrency 2 ─────────────────────────────
    var downloaded = 0;
    var skipped = 0;
    var failed = 0;

    _onProgress(FolderJobDownloading(
      completed: 0,
      total: tasks.length,
      downloaded: 0,
      skipped: 0,
      failed: 0,
    ));

    var index = 0;

    Future<void> runWorker() async {
      while (!_cancelled) {
        final i = index++;
        if (i >= tasks.length) return;
        final (entry, link) = tasks[i];
        try {
          final result = await _download(entry, link, _settings);
          if (result == 'already_exists') {
            skipped++;
          } else {
            downloaded++;
          }
        } catch (_) {
          failed++;
        }
        _onProgress(FolderJobDownloading(
          completed: downloaded + skipped + failed,
          total: tasks.length,
          downloaded: downloaded,
          skipped: skipped,
          failed: failed,
        ));
      }
    }

    await Future.wait([runWorker(), runWorker()]);

    _onProgress(FolderJobDone(
      downloaded: downloaded,
      skipped: skipped,
      failed: failed,
      stoppedAtLimit: stoppedAtLimit,
      wasCancelled: _cancelled,
    ));
```

- [ ] **Step 4: Run all job tests**

```powershell
flutter test test/data/folder_download_job_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/folder_download_job.dart test/data/folder_download_job_test.dart
git commit -m "feat(data): implement FolderDownloadJob download phase"
```

---

### Task 5: `FolderDownloadNotifier` + `folderDownloadProvider` — TDD

**Files:**
- Create: `test/ui/folder_download_notifier_test.dart`
- Modify: `lib/ui/providers.dart`

- [ ] **Step 1: Create `test/ui/folder_download_notifier_test.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/book_downloader.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

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

class _SlowFeedRepo implements FeedRepository {
  late final _completer = _CachedFeedCompleter();

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

class _CachedFeedCompleter {
  final _c = <Function(CachedFeed)>[];
  CachedFeed? _value;

  void complete(CachedFeed v) {
    _value = v;
    for (final f in _c) f(v);
  }

  Future<CachedFeed> get future async {
    if (_value != null) return _value!;
    final p = ProviderContainer(); // just need a Completer
    // ignore: close_sinks
    return Future(() async {
      while (_value == null) {
        await Future.delayed(const Duration(milliseconds: 1));
      }
      return _value!;
    });
  }
}

class _FakeDownloadStorage implements DownloadStorage {
  @override
  Future<bool> exists(List<String> s, String f) async => false;
  @override
  Future<String> write(List<String> s, String f, Stream<List<int>> b) async =>
      'content://fake';
}

class _ConstSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings(target: SystemDownloads());
  @override
  Future<void> save(AppSettings s) async {}
}

ProviderContainer _container({
  FeedRepository? feedRepo,
  BookDownloader? Function()? downloaderFactory,
}) {
  final downloader = downloaderFactory != null
      ? downloaderFactory()
      : BookDownloader(
          MockClient((_) async => http.Response.bytes([1], 200)),
          _FakeDownloadStorage(),
        );
  return ProviderContainer(overrides: [
    feedRepositoryProvider.overrideWithValue(feedRepo ?? _EmptyFeedRepo()),
    bookDownloaderProvider.overrideWithValue(downloader),
    settingsRepositoryProvider.overrideWithValue(_ConstSettingsRepo()),
    safPermissionCheckerProvider.overrideWithValue((_) async => true),
  ]);
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  test('initial state is FolderJobIdle', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });

  test('start() with empty feed ends as FolderJobDone(downloaded: 0)', () async {
    final c = _container();
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    await c.read(folderDownloadProvider.notifier).start(1, Uri.parse('http://x.com'));

    final done = c.read(folderDownloadProvider) as FolderJobDone;
    expect(done.downloaded, 0);
    expect(done.wasCancelled, false);
  });

  test('start() no-op when job is already running', () async {
    final slowRepo = _SlowFeedRepo();
    final c = _container(feedRepo: slowRepo);
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);

    // Start first job (suspends at getFeed)
    final firstFuture = notifier.start(1, Uri.parse('http://x.com'));
    // State set to FolderJobScanning synchronously before first await
    expect(c.read(folderDownloadProvider), isA<FolderJobScanning>());

    // Second start() — guard fires, returns immediately
    await notifier.start(1, Uri.parse('http://x.com/other'));
    expect(c.read(folderDownloadProvider), isA<FolderJobScanning>());

    // Clean up
    slowRepo.complete();
    await firstFuture;
  });

  test('cancel() causes wasCancelled = true in done state', () async {
    final slowRepo = _SlowFeedRepo();
    final c = _container(feedRepo: slowRepo);
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);

    final startFuture = notifier.start(1, Uri.parse('http://x.com'));
    expect(c.read(folderDownloadProvider), isA<FolderJobScanning>());

    notifier.cancel();
    slowRepo.complete();
    await startFuture;

    final done = c.read(folderDownloadProvider) as FolderJobDone;
    expect(done.wasCancelled, isTrue);
  });

  test('dismiss() resets state to FolderJobIdle', () async {
    final c = _container();
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);
    await notifier.start(1, Uri.parse('http://x.com'));

    expect(c.read(folderDownloadProvider), isA<FolderJobDone>());
    notifier.dismiss();
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });
}
```

- [ ] **Step 2: Run to confirm failures**

```powershell
flutter test test/ui/folder_download_notifier_test.dart
```

Expected: compile errors — `folderDownloadProvider` and `FolderDownloadNotifier` not defined.

- [ ] **Step 3: Add `FolderDownloadNotifier` and `folderDownloadProvider` to `lib/ui/providers.dart`**

Add the following imports at the top of `providers.dart` (alongside existing ones):

```dart
import 'package:opds_browser/data/folder_download_job.dart';
```

Then add at the end of the file, after the `_mapError` function:

```dart
// ── Folder download ───────────────────────────────────────────────────────────

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
        downloaded: 0,
        skipped: 0,
        failed: 0,
        stoppedAtLimit: false,
        wasCancelled: true,
      );
      return;
    }

    _job = FolderDownloadJob(
      feedRepository: ref.read(feedRepositoryProvider),
      download: downloader.download,
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

- [ ] **Step 4: Run tests**

```powershell
flutter test test/ui/folder_download_notifier_test.dart
```

Expected: all tests pass. If `_SlowFeedRepo.future` implementation is fragile, simplify it using `dart:async`'s `Completer<CachedFeed>` directly:

```dart
class _SlowFeedRepo implements FeedRepository {
  final _completer = Completer<CachedFeed>();

  void complete() => _completer.complete(CachedFeed(
    feed: const ParsedFeed(title: '', entries: []),
    fetchedAt: DateTime.now(),
    fromCache: false,
  ));

  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
      {bool forceRefresh = false}) => _completer.future;
}
```

Re-run until all pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/folder_download_notifier_test.dart
git commit -m "feat(ui): add FolderDownloadNotifier and folderDownloadProvider"
```

---

### Task 6: `FolderJobBanner` widget — TDD

**Files:**
- Create: `test/ui/folder_job_banner_test.dart`
- Create: `lib/ui/widgets/folder_job_banner.dart`

- [ ] **Step 1: Create `test/ui/folder_job_banner_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/widgets/folder_job_banner.dart';

class _StubNotifier extends Notifier<FolderJobState> {
  _StubNotifier(this._state);
  final FolderJobState _state;
  @override
  FolderJobState build() => _state;
  void set(FolderJobState s) => state = s;
}

Widget _wrap(FolderJobState state) => ProviderScope(
      overrides: [
        folderDownloadProvider
            .overrideWith(() => _StubNotifier(state)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [FolderJobBanner()])),
      ),
    );

void main() {
  testWidgets('hidden when FolderJobIdle', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobIdle()));
    expect(find.byType(FolderJobBanner), findsOneWidget);
    // No visible text content
    expect(find.text('CANCEL'), findsNothing);
    expect(find.text('DISMISS'), findsNothing);
  });

  testWidgets('shows scanning message and CANCEL button', (tester) async {
    await tester.pumpWidget(
        _wrap(const FolderJobScanning(foldersFound: 3)));
    expect(find.textContaining('Scanning folders'), findsOneWidget);
    expect(find.textContaining('3'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'DISMISS'), findsNothing);
  });

  testWidgets('shows downloading message with counts', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDownloading(
      completed: 2,
      total: 5,
      downloaded: 1,
      skipped: 1,
      failed: 0,
    )));
    expect(find.textContaining('Downloading 2 of 5'), findsOneWidget);
    expect(find.textContaining('1 skipped'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
  });

  testWidgets('does not show skipped/failed when zero', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDownloading(
      completed: 1,
      total: 3,
      downloaded: 1,
      skipped: 0,
      failed: 0,
    )));
    expect(find.textContaining('skipped'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('shows summary and DISMISS button when done', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDone(
      downloaded: 4,
      skipped: 1,
      failed: 0,
      stoppedAtLimit: false,
    )));
    expect(find.textContaining('Downloaded: 4'), findsOneWidget);
    expect(find.textContaining('Skipped: 1'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'DISMISS'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsNothing);
  });

  testWidgets('shows Cancelled prefix and Stopped at limit when applicable',
      (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDone(
      downloaded: 0,
      skipped: 0,
      failed: 0,
      stoppedAtLimit: true,
      wasCancelled: true,
    )));
    expect(find.textContaining('Cancelled'), findsOneWidget);
    expect(find.textContaining('Stopped at limit'), findsOneWidget);
  });

  testWidgets('tapping DISMISS calls dismiss() on notifier', (tester) async {
    FolderJobState? newState;
    final notifier = _StubNotifier(const FolderJobDone(
      downloaded: 1, skipped: 0, failed: 0, stoppedAtLimit: false,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [folderDownloadProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (_, ref, __) {
            ref.listen(folderDownloadProvider, (_, s) => newState = s);
            return const Column(children: [FolderJobBanner()]);
          }),
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'DISMISS'));
    await tester.pump();

    expect(newState, isA<FolderJobIdle>());
  });
}
```

- [ ] **Step 2: Run to confirm failures**

```powershell
flutter test test/ui/folder_job_banner_test.dart
```

Expected: compile error — `FolderJobBanner` not found.

- [ ] **Step 3: Create `lib/ui/widgets/folder_job_banner.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';

class FolderJobBanner extends ConsumerWidget {
  const FolderJobBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(folderDownloadProvider);
    if (state is FolderJobIdle) return const SizedBox.shrink();

    final notifier = ref.read(folderDownloadProvider.notifier);

    final String message;
    final Widget trailing;

    switch (state) {
      case FolderJobIdle():
        return const SizedBox.shrink();

      case FolderJobScanning(:final foldersFound):
        message = 'Scanning folders… ($foldersFound found)';
        trailing = TextButton(
          onPressed: notifier.cancel,
          child: const Text('CANCEL'),
        );

      case FolderJobDownloading(
          :final completed,
          :final total,
          :final skipped,
          :final failed
        ):
        final extras = [
          if (skipped > 0) '$skipped skipped',
          if (failed > 0) '$failed failed',
        ];
        message = 'Downloading $completed of $total'
            '${extras.isNotEmpty ? ' · ${extras.join(' · ')}' : ''}';
        trailing = TextButton(
          onPressed: notifier.cancel,
          child: const Text('CANCEL'),
        );

      case FolderJobDone(
          :final downloaded,
          :final skipped,
          :final failed,
          :final stoppedAtLimit,
          :final wasCancelled
        ):
        final parts = <String>[
          if (wasCancelled) 'Cancelled.',
          'Downloaded: $downloaded · Skipped: $skipped · Failed: $failed',
          if (stoppedAtLimit) 'Stopped at limit',
        ];
        message = parts.join(' ');
        trailing = TextButton(
          onPressed: notifier.dismiss,
          child: const Text('DISMISS'),
        );
    }

    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```powershell
flutter test test/ui/folder_job_banner_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/widgets/folder_job_banner.dart test/ui/folder_job_banner_test.dart
git commit -m "feat(ui): add FolderJobBanner widget"
```

---

### Task 7: BrowseScreen wiring — TDD

**Files:**
- Modify: `test/ui/browse_screen_test.dart`
- Modify: `lib/ui/browse_screen.dart`

- [ ] **Step 1: Add folder-job tests to `test/ui/browse_screen_test.dart`**

Add these imports at the top of the test file:

```dart
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/widgets/folder_job_banner.dart';
```

Add a `_FolderJobStub` helper class before `main()`:

```dart
class _FolderJobStub extends Notifier<FolderJobState> {
  _FolderJobStub(this._state);
  final FolderJobState _state;
  @override
  FolderJobState build() => _state;
}
```

Modify `buildApp()` to accept an optional `folderJobState` parameter. Replace the `buildApp` function:

```dart
Widget buildApp({
  required CachedFeed feed,
  List<Favorite> favorites = const [],
  CachedFeed? refreshFeed,
  int catalogId = 1,
  Uri? url,
  void Function(GoRouterState)? onBrowse,
  FolderJobState folderJobState = const FolderJobIdle(),
}) {
  final feedRepo =
      FakeFeedRepository(initialFeed: feed, refreshFeed: refreshFeed);
  final favRepo = FakeFavoritesRepository(initial: favorites);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => BrowseScreen(
          catalogId: catalogId,
          url: url ?? _feedUrl,
        ),
      ),
      GoRoute(
        path: '/browse',
        builder: (_, state) {
          onBrowse?.call(state);
          return const Scaffold(body: Text('sub'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      feedRepositoryProvider.overrideWithValue(feedRepo),
      favoritesRepositoryProvider.overrideWithValue(favRepo),
      folderDownloadProvider
          .overrideWith(() => _FolderJobStub(folderJobState)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
```

Add these new tests at the end of `main()`:

```dart
  group('folder download banner', () {
    testWidgets('banner hidden when FolderJobIdle', (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobIdle(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('CANCEL'), findsNothing);
      expect(find.text('DISMISS'), findsNothing);
    });

    testWidgets('banner shows scanning message during FolderJobScanning',
        (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobScanning(foldersFound: 7),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Scanning folders'), findsOneWidget);
      expect(find.textContaining('7'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
    });

    testWidgets('banner shows downloading progress during FolderJobDownloading',
        (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobDownloading(
          completed: 3, total: 10, downloaded: 2, skipped: 1, failed: 0,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Downloading 3 of 10'), findsOneWidget);
      expect(find.textContaining('1 skipped'), findsOneWidget);
    });

    testWidgets('banner shows summary with DISMISS button when done',
        (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobDone(
          downloaded: 5, skipped: 2, failed: 1, stoppedAtLimit: false,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Downloaded: 5'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'DISMISS'), findsOneWidget);
    });
  });

  group('Download-folder button', () {
    testWidgets('button enabled when idle and feed is loaded', (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobIdle(),
      ));
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('button disabled during FolderJobScanning', (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobScanning(foldersFound: 1),
      ));
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('tapping button shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobIdle(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      await tester.pumpAndSettle();
      expect(find.text('Download folder'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'DOWNLOAD'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run to confirm failures**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: new tests fail (banner not found, button still null).

- [ ] **Step 3: Modify `lib/ui/browse_screen.dart`**

Add imports at the top:

```dart
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/widgets/folder_job_banner.dart';
```

In `_BrowseContent.build()`, add a `folderDownloadProvider` watch at the top of the method:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (catalogId, url) = args;           // already present, unchanged
    final entries = state.feed.feed.entries; // already present, unchanged
    final jobState = ref.watch(folderDownloadProvider); // ADD THIS LINE
```

Replace the existing disabled Download-folder `IconButton` action:

```dart
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: null,
          ),
```

with:

```dart
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Download folder',
            onPressed:
                (jobState is FolderJobIdle || jobState is FolderJobDone)
                    ? () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Download folder'),
                            content: const Text(
                              'Download all books in this folder and its '
                              'subfolders? This may be a large amount of data.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('CANCEL'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('DOWNLOAD'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          ref
                              .read(folderDownloadProvider.notifier)
                              .start(catalogId, url);
                        }
                      }
                    : null,
          ),
```

In the `body:` `Column`, add `const FolderJobBanner()` after the `Expanded`:

```dart
      body: Column(
        children: [
          if (state.isRefreshing) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              // ... unchanged ...
            ),
          ),
          const FolderJobBanner(),   // ADD THIS LINE
        ],
      ),
```

- [ ] **Step 4: Run tests**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all tests pass including the new ones.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/browse_screen.dart test/ui/browse_screen_test.dart
git commit -m "feat(ui): wire folder download button and banner in BrowseScreen"
```

---

### Task 8: Single-book snackbar dismiss fix

**Files:**
- Modify: `lib/ui/browse_screen.dart`

- [ ] **Step 1: Add `showCloseIcon: true` to both SnackBars in `_BrowseContent.build()`**

Locate the `ref.listen(lastDownloadResultProvider, ...)` block. The current SnackBar construction:

```dart
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
```

Replace with:

```dart
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(msg),
          action: result.alreadyExisted
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => OpenFilex.open(result.contentUri),
                ),
        ),
      );
```

- [ ] **Step 2: Run existing browse_screen tests to confirm no regression**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```powershell
git add lib/ui/browse_screen.dart
git commit -m "fix(ui): add close icon to single-book download snackbar"
```

---

### Task 9: Quality gate

**Files:** none

- [ ] **Step 1: Run static analysis**

```powershell
flutter analyze
```

Expected: no issues. Common fixes if issues appear:
- Missing `const` on state constructors → add `const`
- Unused import → remove it
- `switch` not exhaustive → add missing cases

- [ ] **Step 2: Run full test suite**

```powershell
flutter test
```

Expected: all tests pass.

- [ ] **Step 3: If any failures, fix and commit**

```powershell
git add <affected files>
git commit -m "fix: address analyze/test failures"
```

- [ ] **Step 4: Canonical quality gate**

```powershell
dart run tool/check.dart
```

Expected: exits 0.

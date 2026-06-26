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

Future<String> _noOp(BookEntry e, AcquisitionLink l, AppSettings s,
        {String? inferredSeries}) async =>
    'content://ok';

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

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
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

    test('depth > 10 skipped; stoppedAtLimit = true in FolderJobDone', () async {
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

  group('download phase', () {
    test('run() with books emits FolderJobTreeReady (not FolderJobDone)', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_book('1'), _book('2')]);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      expect(states.last, isA<FolderJobTreeReady>());
    });

    test('run() with single book emits FolderJobTreeReady', () async {
      final repo = _FakeFeedRepository();
      final root = Uri.parse('http://example.com/root');
      repo.addFeed(root, [_book('1')]);

      final states = <FolderJobState>[];
      await _makeJob(repo, states: states).run(1, root);

      expect(states.last, isA<FolderJobTreeReady>());
    });
  });

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

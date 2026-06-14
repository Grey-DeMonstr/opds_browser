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
      // 500 sub-folders
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

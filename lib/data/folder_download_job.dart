// ignore_for_file: prefer_initializing_formals

import 'dart:collection';

import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';

typedef DownloadFn = Future<String> Function(
    BookEntry entry, AcquisitionLink link, AppSettings settings,
    {String? inferredSeries});

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

// ── Job ───────────────────────────────────────────────────────────────────────

class FolderDownloadJob {
  FolderDownloadJob({
    required FeedRepository feedRepository,
    required DownloadFn downloadFn,
    required AppSettings settings,
    required void Function(FolderJobState) onProgress,
  })  : _feedRepository = feedRepository,
        _download = downloadFn,
        _settings = settings,
        _onProgress = onProgress;

  final FeedRepository _feedRepository;
  final DownloadFn _download;
  final AppSettings _settings;
  final void Function(FolderJobState) _onProgress;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

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
        } else if (entry is BookEntry &&
            entry.acquisitionLinks.isNotEmpty &&
            tasks.length < 2000) {
          tasks.add((entry, folderPreferredLink(entry.acquisitionLinks)));
        }
      }
      if (tasks.length >= 2000) stoppedAtLimit = true;
    }

    final emptyRoot = DownloadFolder(title: '', children: []);

    if (_cancelled || tasks.isEmpty) {
      _onProgress(FolderJobDone(
        root: emptyRoot,
        results: const {},
        stoppedAtLimit: stoppedAtLimit,
        wasCancelled: _cancelled,
      ));
      return;
    }

    // ── Phase 2: download with concurrency 2 ─────────────────────────────
    final results = <Uri, BookDownloadResult>{};

    _onProgress(FolderJobDownloading(
      root: emptyRoot,
      results: Map.unmodifiable(results),
      total: tasks.length,
      completedCount: 0,
    ));

    var index = 0;

    Future<void> runWorker() async {
      while (!_cancelled) {
        final i = index++; // safe: no await between read and write (Dart single-isolate)
        if (i >= tasks.length) return;
        final (entry, link) = tasks[i];
        final bookUri = link.url;
        try {
          final result = await _download(entry, link, _settings, inferredSeries: null);
          results[bookUri] = BookDownloadResult(
            status: result == 'already_exists'
                ? BookDownloadStatus.skipped
                : BookDownloadStatus.done,
          );
        } catch (e) {
          results[bookUri] = BookDownloadResult(
            status: BookDownloadStatus.failed,
            error: e.toString(),
          );
        }
        _onProgress(FolderJobDownloading(
          root: emptyRoot,
          results: Map.unmodifiable(results),
          total: tasks.length,
          completedCount: results.length,
        ));
      }
    }

    await Future.wait([runWorker(), runWorker()]);

    _onProgress(FolderJobDone(
      root: emptyRoot,
      results: Map.unmodifiable(results),
      stoppedAtLimit: stoppedAtLimit,
      wasCancelled: _cancelled,
    ));
  }
}

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
        await Future<void>.delayed(_downloadDelay);
      }
    }

    _onProgress(FolderJobDone(
      root: displayRoot,
      results: Map.unmodifiable(results),
      wasCancelled: _cancelled,
      stoppedAtLimit: _stoppedAtLimit,
    ));
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

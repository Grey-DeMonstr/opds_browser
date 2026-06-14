// ignore_for_file: prefer_initializing_formals

import 'dart:collection';

import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';

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

    // ── Phase 2: Download (placeholder — full impl in Task 4) ─────────────
    var downloaded = 0;
    var failed = 0;

    for (final (entry, link) in tasks) {
      if (_cancelled) break;
      try {
        await _download(entry, link, _settings);
        downloaded++;
      } catch (_) {
        failed++;
      }
    }

    _onProgress(FolderJobDone(
      downloaded: downloaded,
      skipped: 0,
      failed: failed,
      stoppedAtLimit: stoppedAtLimit,
      wasCancelled: _cancelled,
    ));
  }
}

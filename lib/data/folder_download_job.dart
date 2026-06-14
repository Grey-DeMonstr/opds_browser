// ignore_for_file: prefer_initializing_formals

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

  // ignore: unused_field
  final FeedRepository _feedRepository;
  // ignore: unused_field
  final DownloadFn _download;
  // ignore: unused_field
  final AppSettings _settings;
  // ignore: unused_field
  final void Function(FolderJobState) _onProgress;

  // ignore: unused_field
  bool _cancelled = false;
  void cancel() => _cancelled = true;

  Future<void> run(int catalogId, Uri startUrl) async {
    // implemented in Tasks 3 and 4
  }
}

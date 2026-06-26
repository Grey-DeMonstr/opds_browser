import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  test('initial state is FolderJobIdle', () {
    final c = _container();
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });

  test('start() with empty feed ends as FolderJobDone(downloaded: 0)', () async {
    final c = _container();

    await c.read(settingsProvider.future);
    await c.read(folderDownloadProvider.notifier).start(1, Uri.parse('http://x.com'));

    final done = c.read(folderDownloadProvider) as FolderJobDone;
    expect(done.downloaded, 0);
    expect(done.wasCancelled, false);
  });

  test('start() no-op when job is already scanning', () async {
    final slowRepo = _SlowFeedRepo();
    final c = _container(feedRepo: slowRepo);

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

    await c.read(settingsProvider.future);
    final notifier = c.read(folderDownloadProvider.notifier);
    await notifier.start(1, Uri.parse('http://x.com'));

    expect(c.read(folderDownloadProvider), isA<FolderJobDone>());
    notifier.dismiss();
    expect(c.read(folderDownloadProvider), isA<FolderJobIdle>());
  });
}

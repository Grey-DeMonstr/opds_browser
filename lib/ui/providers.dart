import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/book_downloader.dart';
import 'package:opds_browser/data/caching_feed_repository.dart';
import 'package:opds_browser/data/file_system_download_storage.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/data/saf_download_storage.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/data/sqflite_catalog_repository.dart';
import 'package:opds_browser/data/sqflite_favorites_repository.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:saf_util/saf_util.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final opdsClientProvider = Provider<OpdsClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return Opds1Client(client);
});

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SqfliteCatalogRepository(ref.watch(appDatabaseProvider)),
);

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => SqfliteFavoritesRepository(ref.watch(appDatabaseProvider)),
);

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => CachingFeedRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(opdsClientProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SharedPrefsSettingsRepository(),
);

class CatalogsNotifier extends AsyncNotifier<List<Catalog>> {
  @override
  Future<List<Catalog>> build() async {
    return ref.watch(catalogRepositoryProvider).getAll();
  }

  Future<void> add(String title, Uri rootUrl) async {
    final repo = ref.read(catalogRepositoryProvider);
    await repo.add(title, rootUrl);
    state = AsyncData(await repo.getAll());
  }

  Future<void> updateCatalog(Catalog catalog) async {
    final repo = ref.read(catalogRepositoryProvider);
    await repo.update(catalog);
    state = AsyncData(await repo.getAll());
  }

  Future<void> delete(int catalogId) async {
    final repo = ref.read(catalogRepositoryProvider);
    await repo.delete(catalogId);
    state = AsyncData(await repo.getAll());
  }
}

final catalogsProvider =
    AsyncNotifierProvider<CatalogsNotifier, List<Catalog>>(
        CatalogsNotifier.new);

class FavoritesNotifier extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() async {
    return ref.watch(favoritesRepositoryProvider).getAll();
  }

  Future<void> remove(int favoriteId) async {
    final repo = ref.read(favoritesRepositoryProvider);
    await repo.remove(favoriteId);
    state = AsyncData(await repo.getAll());
  }

  Future<void> toggle(int catalogId, Uri url, String title) async {
    final repo = ref.read(favoritesRepositoryProvider);
    final currentFavorites = state.value;
    final existing = currentFavorites?.where(
      (f) => f.catalogId == catalogId && f.url == url,
    ).firstOrNull;
    if (existing != null) {
      await repo.remove(existing.id);
    } else {
      await repo.add(catalogId, url, title);
    }
    state = AsyncData(await repo.getAll());
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(
        FavoritesNotifier.new);

// ── Browse screen ─────────────────────────────────────────────────────────────

class BrowseState {
  final CachedFeed feed;
  final bool isRefreshing;

  const BrowseState({required this.feed, this.isRefreshing = false});

  BrowseState copyWith({CachedFeed? feed, bool? isRefreshing}) => BrowseState(
        feed: feed ?? this.feed,
        isRefreshing: isRefreshing ?? this.isRefreshing,
      );
}

typedef BrowseArgs = (int, Uri);

class BrowseNotifier extends AsyncNotifier<BrowseState> {
  late BrowseArgs _args;

  void _setArgs(BrowseArgs args) {
    _args = args;
  }

  @override
  Future<BrowseState> build() async {
    final (catalogId, url) = _args;
    final feed =
        await ref.read(feedRepositoryProvider).getFeed(catalogId, url);
    return BrowseState(feed: feed);
  }

  Future<void> refresh() async {
    final currentState = state;
    if (currentState is! AsyncData<BrowseState>) return;
    final old = currentState.value;
    state = AsyncData(old.copyWith(isRefreshing: true));
    try {
      final (catalogId, url) = _args;
      final feed = await ref
          .read(feedRepositoryProvider)
          .getFeed(catalogId, url, forceRefresh: true);
      state = AsyncData(BrowseState(feed: feed));
    } catch (_) {
      state = AsyncData(old.copyWith(isRefreshing: false));
      rethrow;
    }
  }
}

final browseProvider = AsyncNotifierProvider.autoDispose
    .family<BrowseNotifier, BrowseState, BrowseArgs>((args) {
  return BrowseNotifier().._setArgs(args);
});

final isFavoriteProvider =
    Provider.autoDispose.family<bool, BrowseArgs>((ref, args) {
  final (catalogId, url) = args;
  final favoritesAsync = ref.watch(favoritesProvider);
  return favoritesAsync.whenData((favorites) {
        return favorites.any((f) => f.catalogId == catalogId && f.url == url);
      }).value ??
      false;
});

// ── Settings ──────────────────────────────────────────────────────────────────

final safPermissionCheckerProvider =
    Provider<Future<bool> Function(String)>((ref) {
  if (!Platform.isAndroid) {
    return (path) => Directory(path).exists();
  }
  return (uri) => SafUtil().hasPersistedPermission(uri, checkWrite: true);
});

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  bool permissionRevoked = false;

  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    final checker = ref.read(safPermissionCheckerProvider);
    var settings = await repo.load();
    if (settings.target is CustomSafFolder) {
      final uri = (settings.target as CustomSafFolder).uriString;
      final hasPermission = await checker(uri);
      if (!hasPermission) {
        settings = settings.copyWith(target: const SystemDownloads());
        await repo.save(settings);
        permissionRevoked = true;
      }
    }
    return settings;
  }

  Future<bool> pickCustomFolder() async {
    if (!Platform.isAndroid) {
      final dirPath = await getDirectoryPath();
      if (dirPath == null) return false;
      final name = p.basename(dirPath);
      final newSettings = (state.value ??
              const AppSettings(target: SystemDownloads()))
          .copyWith(
              target: CustomSafFolder(dirPath, name.isEmpty ? dirPath : name));
      await ref.read(settingsRepositoryProvider).save(newSettings);
      state = AsyncData(newSettings);
      return true;
    }
    final dir = await SafUtil().pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );
    if (dir == null) return false;
    final name = dir.name.isNotEmpty ? dir.name : dir.uri;
    final newSettings = (state.value ??
            const AppSettings(target: SystemDownloads()))
        .copyWith(target: CustomSafFolder(dir.uri, name));
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
    return true;
  }

  Future<void> setSystemDownloads() async {
    final current = state.value;
    if (current == null) return;
    final newSettings = current.copyWith(target: const SystemDownloads());
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }

  Future<void> setCreateAuthorFolder(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newSettings = current.copyWith(createAuthorFolder: value);
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }

  Future<void> setCreateSeriesFolder(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newSettings = current.copyWith(createSeriesFolder: value);
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final downloadStorageProvider = Provider<DownloadStorage?>((ref) {
  final target = ref.watch(settingsProvider).value?.target;
  return switch (target) {
    SystemDownloads() when Platform.isAndroid => null,
    SystemDownloads() => FileSystemDownloadStorage.downloads(),
    CustomSafFolder(uriString: final uri) when Platform.isAndroid =>
      SafDownloadStorage(uri),
    CustomSafFolder(uriString: final path) => FileSystemDownloadStorage(path),
    null => null,
  };
});

// ── Download ──────────────────────────────────────────────────────────────────

sealed class DownloadState {
  const DownloadState();
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class DownloadInProgress extends DownloadState {
  const DownloadInProgress();
}

class DownloadDone extends DownloadState {
  const DownloadDone({
    required this.contentUri,
    required this.fileName,
    required this.alreadyExisted,
    required this.mimeType,
  });

  final String contentUri;
  final String fileName;
  final bool alreadyExisted;
  final String mimeType;
}

class DownloadFailed extends DownloadState {
  const DownloadFailed(this.message);
  final String message;
}

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final bookDownloaderProvider = Provider<BookDownloader?>((ref) {
  final storage = ref.watch(downloadStorageProvider);
  if (storage == null) return null;
  return BookDownloader(ref.watch(httpClientProvider), storage);
});

class _LastDownloadResultNotifier extends Notifier<DownloadDone?> {
  @override
  DownloadDone? build() => null;

  // ignore: use_setters_to_change_properties
  void set(DownloadDone value) => state = value;

  void clear() => state = null;
}

final lastDownloadResultProvider =
    NotifierProvider<_LastDownloadResultNotifier, DownloadDone?>(
  _LastDownloadResultNotifier.new,
);

class DownloadNotifier extends Notifier<DownloadState> {
  late Uri _linkUrl;

  void _setUrl(Uri url) => _linkUrl = url;

  @override
  DownloadState build() => const DownloadIdle();

  Future<void> start(
    BookEntry entry,
    AppSettings settings, {
    String? inferredSeries,
  }) async {
    if (state is DownloadInProgress) return;
    state = const DownloadInProgress();

    final downloader = ref.read(bookDownloaderProvider);
    if (downloader == null) {
      state = const DownloadFailed('Downloads are not supported on this platform.');
      return;
    }

    final link = entry.acquisitionLinks.firstWhere((l) => l.url == _linkUrl);
    final fileName = buildFileName(entry, link, settings, inferredSeries: inferredSeries);

    try {
      final result = await downloader.download(
        entry,
        link,
        settings,
        inferredSeries: inferredSeries,
      );
      final done = result == 'already_exists'
          ? DownloadDone(
              contentUri: '',
              fileName: fileName,
              alreadyExisted: true,
              mimeType: link.mimeType,
            )
          : DownloadDone(
              contentUri: result,
              fileName: fileName,
              alreadyExisted: false,
              mimeType: link.mimeType,
            );
      ref.read<_LastDownloadResultNotifier>(lastDownloadResultProvider.notifier).set(done);
      state = done;
    } on OpdsException catch (e) {
      state = DownloadFailed(_mapError(e));
    } catch (e) {
      state = DownloadFailed('Unexpected error: $e');
    }
  }
}

final downloadNotifierProvider =
    NotifierProvider.family<DownloadNotifier, DownloadState, Uri>(
  (url) => DownloadNotifier().._setUrl(url),
);

String _mapError(OpdsException e) => switch (e) {
      NetworkException() =>
        'Network error. Check your connection and try again.',
      HttpStatusException(statusCode: 404) =>
        'The book file was not found on the server (HTTP 404).',
      HttpStatusException(statusCode: 401 || 403) =>
        'This catalogue requires authentication, which is not supported.',
      HttpStatusException(statusCode: final code) => 'Server error (HTTP $code).',
      ParseException() => 'The server response is not a valid OPDS feed.',
      UnsupportedProtocolException() => 'Not a supported OPDS catalogue.',
    };

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
    final gen = _jobGen;
    await _job!.download(checkedBooks);
    // Only clear _job if gen hasn't been superseded (e.g. by reset())
    if (_jobGen == gen) _job = null;
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

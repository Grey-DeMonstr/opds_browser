import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

abstract interface class CatalogRepository {
  Future<List<Catalog>> getAll();
  Future<Catalog> add(String title, Uri rootUrl);
  Future<void> update(Catalog catalog);
  Future<void> delete(int catalogId);
}

abstract interface class FeedRepository {
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  });
}

abstract interface class FavoritesRepository {
  Future<List<Favorite>> getAll();
  Future<void> add(int catalogId, Uri url, String title);
  Future<void> remove(int favoriteId);
  Future<bool> isFavorite(int catalogId, Uri url);
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

abstract interface class DownloadStorage {
  /// Returns true if a file with this path already exists.
  Future<bool> exists(List<String> pathSegments, String fileName);

  /// Streams [bytes] into the file, creating intermediate folders.
  /// Returns an opaque locator usable by open_filex (content URI string).
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
    String mimeType,
  );
}

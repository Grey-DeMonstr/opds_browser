import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/caching_feed_repository.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/data/sqflite_catalog_repository.dart';
import 'package:opds_browser/data/sqflite_favorites_repository.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

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

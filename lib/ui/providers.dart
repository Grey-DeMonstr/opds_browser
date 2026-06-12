import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/caching_feed_repository.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/data/sqflite_catalog_repository.dart';
import 'package:opds_browser/data/sqflite_favorites_repository.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final opdsClientProvider = Provider<OpdsClient>(
  (ref) => Opds1Client(http.Client()),
);

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

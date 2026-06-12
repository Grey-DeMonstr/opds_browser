import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/start_screen.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class FakeCatalogRepository implements CatalogRepository {
  final List<Catalog> _data;
  var _nextId = 1;

  FakeCatalogRepository({List<Catalog> initial = const []})
      : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId =
          initial.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Catalog>> getAll() async => List.unmodifiable(_data);

  @override
  Future<Catalog> add(String title, Uri rootUrl) async {
    final c = Catalog(
        id: _nextId++, title: title, rootUrl: rootUrl, protocol: 'opds1');
    _data.add(c);
    return c;
  }

  @override
  Future<void> update(Catalog catalog) async {
    final i = _data.indexWhere((c) => c.id == catalog.id);
    if (i >= 0) _data[i] = catalog;
  }

  @override
  Future<void> delete(int catalogId) async {
    _data.removeWhere((c) => c.id == catalogId);
  }
}

class FakeFavoritesRepository implements FavoritesRepository {
  final List<Favorite> _data;
  var _nextId = 1;

  FakeFavoritesRepository({List<Favorite> initial = const []})
      : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId =
          initial.map((f) => f.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Favorite>> getAll() async => List.unmodifiable(_data);

  @override
  Future<void> add(int catalogId, Uri url, String title) async {
    _data.add(Favorite(
      id: _nextId++,
      catalogId: catalogId,
      url: url,
      title: title,
      sortOrder: _data.length,
    ));
  }

  @override
  Future<void> remove(int favoriteId) async {
    _data.removeWhere((f) => f.id == favoriteId);
  }

  @override
  Future<bool> isFavorite(int catalogId, Uri url) async =>
      _data.any((f) => f.catalogId == catalogId && f.url == url);
}

class FakeOpdsClient implements OpdsClient {
  final bool probeResult;
  FakeOpdsClient({this.probeResult = true});

  @override
  Future<ParsedFeed> fetchFeed(Uri url) => throw UnimplementedError();

  @override
  Future<bool> probe(Uri url) async => probeResult;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

GoRouter _makeRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const StartScreen()),
      GoRoute(path: '/browse', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
    ],
  );
}

Widget buildApp({
  List<Catalog> catalogs = const [],
  List<Favorite> favorites = const [],
  bool probeResult = true,
  GoRouter? router,
}) {
  return ProviderScope(
    overrides: [
      catalogRepositoryProvider
          .overrideWithValue(FakeCatalogRepository(initial: catalogs)),
      favoritesRepositoryProvider
          .overrideWithValue(FakeFavoritesRepository(initial: favorites)),
      opdsClientProvider
          .overrideWithValue(FakeOpdsClient(probeResult: probeResult)),
    ],
    child: MaterialApp.router(routerConfig: router ?? _makeRouter()),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('empty state: shows hint text and FAB', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('No catalogues yet. Tap + to add one.'), findsOneWidget);
    expect(find.text('Add catalogue'), findsOneWidget); // FAB label
  });
}

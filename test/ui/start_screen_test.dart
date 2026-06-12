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

  testWidgets('catalog list: renders two catalogs with titles', (tester) async {
    final catalogs = [
      Catalog(
          id: 1,
          title: 'Project Gutenberg',
          rootUrl: Uri.parse('https://gutenberg.org/opds'),
          protocol: 'opds1'),
      Catalog(
          id: 2,
          title: 'Standard Ebooks',
          rootUrl: Uri.parse('https://standardebooks.org/opds'),
          protocol: 'opds1'),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs));
    await tester.pumpAndSettle();

    expect(find.text('Project Gutenberg'), findsOneWidget);
    expect(find.text('Standard Ebooks'), findsOneWidget);
    // Hint text must NOT appear when list is non-empty
    expect(
        find.text('No catalogues yet. Tap + to add one.'), findsNothing);
  });

  testWidgets('favorites section: hidden when list is empty', (tester) async {
    final catalogs = [
      Catalog(
          id: 1,
          title: 'Gutenberg',
          rootUrl: Uri.parse('https://gutenberg.org/opds'),
          protocol: 'opds1'),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs, favorites: []));
    await tester.pumpAndSettle();

    expect(find.text('Favourites'), findsNothing);
  });

  testWidgets('favorites section: shows when non-empty', (tester) async {
    final catalogs = [
      Catalog(
          id: 1,
          title: 'Gutenberg',
          rootUrl: Uri.parse('https://gutenberg.org/opds'),
          protocol: 'opds1'),
    ];
    final favorites = [
      Favorite(
          id: 1,
          catalogId: 1,
          url: Uri.parse('https://gutenberg.org/opds/science'),
          title: 'Science',
          sortOrder: 0),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs, favorites: favorites));
    await tester.pumpAndSettle();

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Science'), findsOneWidget);
  });

  testWidgets('FAB opens Add dialog with Title and URL fields', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'URL'), findsOneWidget);
  });

  testWidgets('dialog: shows validation error for empty title', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    // Leave title empty, fill in URL
    await tester.enterText(find.widgetWithText(TextFormField, 'URL'), 'example.com');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
  });

  testWidgets('dialog: add catalog when probe passes — catalog appears in list',
      (tester) async {
    await tester.pumpWidget(buildApp(probeResult: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'My Library');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://library.example.com/opds');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.byType(AlertDialog), findsNothing);
    // Catalog should appear in the list
    expect(find.text('My Library'), findsOneWidget);
  });

  testWidgets('dialog: probe failure shows error and Save anyway button',
      (tester) async {
    await tester.pumpWidget(buildApp(probeResult: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'Bad Feed');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://notopds.example.com');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog must stay open
    expect(find.byType(AlertDialog), findsOneWidget);
    // Error text must be shown
    expect(find.text('Not a supported OPDS catalogue'), findsOneWidget);
    // Save anyway button must be visible
    expect(find.widgetWithText(TextButton, 'Save anyway'), findsOneWidget);
  });

  testWidgets('dialog: Save anyway saves without re-probing', (tester) async {
    await tester.pumpWidget(buildApp(probeResult: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'Force Save');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://notopds.example.com');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Save anyway'));
    await tester.pumpAndSettle();

    // Dialog must be dismissed and catalog saved
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Force Save'), findsOneWidget);
  });

  testWidgets('dialog: edit mode pre-fills title and URL', (tester) async {
    final catalog = Catalog(
        id: 1,
        title: 'Project Gutenberg',
        rootUrl: Uri.parse('https://gutenberg.org/opds'),
        protocol: 'opds1');
    await tester.pumpWidget(buildApp(catalogs: [catalog]));
    await tester.pumpAndSettle();

    // Tap the popup menu trailing button on the catalog tile
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // Pre-filled title — check first EditableText controller
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Project Gutenberg',
    );
  });
}

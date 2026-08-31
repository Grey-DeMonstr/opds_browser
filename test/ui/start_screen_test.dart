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
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/fading_rule.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class FakeCatalogRepository implements CatalogRepository {
  final List<Catalog> _data;
  var _nextId = 1;

  FakeCatalogRepository({List<Catalog> initial = const []})
    : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId = initial.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Catalog>> getAll() async => List.unmodifiable(_data);

  @override
  Future<Catalog> add(String title, Uri rootUrl) async {
    final c = Catalog(
      id: _nextId++,
      title: title,
      rootUrl: rootUrl,
      protocol: 'opds1',
    );
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
      _nextId = initial.map((f) => f.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Favorite>> getAll() async => List.unmodifiable(_data);

  @override
  Future<void> add(int catalogId, Uri url, String title) async {
    _data.add(
      Favorite(
        id: _nextId++,
        catalogId: catalogId,
        url: url,
        title: title,
        sortOrder: _data.length,
      ),
    );
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
  @override
  Future<String?> resolveSearchTemplate(SearchLink link) async => null;
  final bool probeResult;
  FakeOpdsClient({this.probeResult = true});

  @override
  Future<ParsedFeed> fetchFeed(Uri url) => throw UnimplementedError();

  @override
  Future<bool> probe(Uri url) async => probeResult;
}

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier({this.initial = const AppSettings()});

  final AppSettings initial;
  int pickCalls = 0;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<bool> pickCustomFolder() async {
    pickCalls++;
    state = AsyncData(
      const AppSettings(target: CustomSafFolder('content://picked', 'Lib')),
    );
    return true;
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

GoRouter _makeRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const StartScreen()),
      GoRoute(path: '/browse', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/library', builder: (_, _) => const Text('LIBRARY')),
    ],
  );
}

Widget buildApp({
  List<Catalog> catalogs = const [],
  List<Favorite> favorites = const [],
  bool probeResult = true,
  GoRouter? router,
  SettingsNotifier? settingsNotifier,
}) {
  return ProviderScope(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(initial: catalogs),
      ),
      favoritesRepositoryProvider.overrideWithValue(
        FakeFavoritesRepository(initial: favorites),
      ),
      opdsClientProvider.overrideWithValue(
        FakeOpdsClient(probeResult: probeResult),
      ),
      settingsProvider.overrideWith(
        () => settingsNotifier ?? FakeSettingsNotifier(),
      ),
    ],
    child: MaterialApp.router(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router ?? _makeRouter(),
    ),
  );
}

// ── Fixtures ────────────────────────────────────────────────────────────────

final _gutenberg = Catalog(
  id: 1,
  title: 'Project Gutenberg',
  rootUrl: Uri.parse('https://gutenberg.org/opds'),
  protocol: 'opds1',
);

final _science = Favorite(
  id: 1,
  catalogId: 1,
  url: Uri.parse('https://gutenberg.org/opds/science'),
  title: 'Science',
  sortOrder: 0,
);

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('catalogue list is inset above the system navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: buildApp(),
      ),
    );
    await tester.pumpAndSettle();

    final bottom = tester.getRect(find.byType(CustomScrollView)).bottom;
    expect(bottom, lessThanOrEqualTo(600 - 48));
  });

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
        protocol: 'opds1',
      ),
      Catalog(
        id: 2,
        title: 'Standard Ebooks',
        rootUrl: Uri.parse('https://standardebooks.org/opds'),
        protocol: 'opds1',
      ),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs));
    await tester.pumpAndSettle();

    expect(find.text('Project Gutenberg'), findsOneWidget);
    expect(find.text('Standard Ebooks'), findsOneWidget);
    // Hint text must NOT appear when list is non-empty
    expect(find.text('No catalogues yet. Tap + to add one.'), findsNothing);
  });

  testWidgets('favorites section: hidden when list is empty', (tester) async {
    final catalogs = [
      Catalog(
        id: 1,
        title: 'Gutenberg',
        rootUrl: Uri.parse('https://gutenberg.org/opds'),
        protocol: 'opds1',
      ),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs, favorites: []));
    await tester.pumpAndSettle();

    expect(find.text('FAVOURITES'), findsNothing);
  });

  testWidgets('favorites section: shows when non-empty', (tester) async {
    final catalogs = [
      Catalog(
        id: 1,
        title: 'Gutenberg',
        rootUrl: Uri.parse('https://gutenberg.org/opds'),
        protocol: 'opds1',
      ),
    ];
    final favorites = [
      Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://gutenberg.org/opds/science'),
        title: 'Science',
        sortOrder: 0,
      ),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs, favorites: favorites));
    await tester.pumpAndSettle();

    expect(find.text('FAVOURITES'), findsOneWidget);
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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL'),
      'example.com',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
  });

  testWidgets(
    'dialog: add catalog when probe passes — catalog appears in list',
    (tester) async {
      await tester.pumpWidget(buildApp(probeResult: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add catalogue'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'My Library',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'),
        'https://library.example.com/opds',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.byType(AlertDialog), findsNothing);
      // Catalog should appear in the list
      expect(find.text('My Library'), findsOneWidget);
    },
  );

  testWidgets('dialog: probe failure shows error and Save anyway button', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(probeResult: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Bad Feed',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL'),
      'https://notopds.example.com',
    );
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
      find.widgetWithText(TextFormField, 'Title'),
      'Force Save',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL'),
      'https://notopds.example.com',
    );
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
      protocol: 'opds1',
    );
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

  testWidgets('delete: tapping Delete shows confirmation dialog', (
    tester,
  ) async {
    final catalog = Catalog(
      id: 1,
      title: 'My Catalog',
      rootUrl: Uri.parse('https://example.com/opds'),
      protocol: 'opds1',
    );
    await tester.pumpWidget(buildApp(catalogs: [catalog]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete catalogue?'), findsOneWidget);
    expect(
      find.text('This will also remove its favourites and cached feeds.'),
      findsOneWidget,
    );
  });

  testWidgets('delete: confirming removes catalog from list', (tester) async {
    final catalog = Catalog(
      id: 1,
      title: 'My Catalog',
      rootUrl: Uri.parse('https://example.com/opds'),
      protocol: 'opds1',
    );
    await tester.pumpWidget(buildApp(catalogs: [catalog]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Tap the destructive Delete button inside the confirmation dialog
    final deleteButtons = find.widgetWithText(TextButton, 'Delete');
    await tester.tap(deleteButtons.last); // confirmation dialog's Delete
    await tester.pumpAndSettle();

    expect(find.text('My Catalog'), findsNothing);
    expect(find.text('No catalogues yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('catalog row tap navigates to /browse with correct params', (
    tester,
  ) async {
    final catalog = Catalog(
      id: 42,
      title: 'My Library',
      rootUrl: Uri.parse('https://library.example.com/opds'),
      protocol: 'opds1',
    );

    String? capturedUri;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const StartScreen()),
        GoRoute(
          path: '/browse',
          builder: (_, state) {
            capturedUri = state.uri.toString();
            return const SizedBox();
          },
        ),
        GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(buildApp(catalogs: [catalog], router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Library'));
    await tester.pumpAndSettle();

    expect(capturedUri, isNotNull);
    expect(capturedUri, contains('catalogId=42'));
    expect(capturedUri, contains('url='));
  });

  testWidgets('remove favourite: item disappears after Remove tapped', (
    tester,
  ) async {
    final catalog = Catalog(
      id: 1,
      title: 'Gutenberg',
      rootUrl: Uri.parse('https://gutenberg.org/opds'),
      protocol: 'opds1',
    );
    final favorite = Favorite(
      id: 1,
      catalogId: 1,
      url: Uri.parse('https://gutenberg.org/opds/science'),
      title: 'Science',
      sortOrder: 0,
    );

    await tester.pumpWidget(
      buildApp(catalogs: [catalog], favorites: [favorite]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsOneWidget);

    // Tap the PopupMenuButton on the favorite tile (first one on screen)
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove from favourites'));
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsNothing);
  });

  testWidgets('library icon button is present in AppBar', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_library_outlined), findsOneWidget);
  });

  testWidgets('section labels are set in caps', (tester) async {
    await tester.pumpWidget(
      buildApp(catalogs: [_gutenberg], favorites: [_science]),
    );
    await tester.pumpAndSettle();

    expect(find.text('FAVOURITES'), findsOneWidget);
    expect(find.text('CATALOGUES'), findsOneWidget);
  });

  testWidgets('favourite row is marked with the first letter of its title', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(catalogs: [_gutenberg], favorites: [_science]),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('favorite-1')),
        matching: find.text('S'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('favourite mark uppercases a non-ASCII initial', (tester) async {
    final favorite = Favorite(
      id: 1,
      catalogId: 1,
      url: Uri.parse('https://gutenberg.org/opds/gromyko'),
      title: 'émile zola',
      sortOrder: 0,
    );
    await tester.pumpWidget(
      buildApp(catalogs: [_gutenberg], favorites: [favorite]),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('favorite-1')),
        matching: find.text('É'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('favourite row names its parent catalogue', (tester) async {
    await tester.pumpWidget(
      buildApp(catalogs: [_gutenberg], favorites: [_science]),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('favorite-1')),
        matching: find.text('Project Gutenberg'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('catalogue row shows its URL without the scheme', (tester) async {
    await tester.pumpWidget(buildApp(catalogs: [_gutenberg]));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('catalog-1')),
        matching: find.text('gutenberg.org/opds'),
      ),
      findsOneWidget,
    );
    expect(find.text('https://gutenberg.org/opds'), findsNothing);
  });

  testWidgets('catalogue row is marked with a feed icon', (tester) async {
    await tester.pumpWidget(buildApp(catalogs: [_gutenberg]));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('catalog-1')),
        matching: find.byIcon(Icons.rss_feed),
      ),
      findsOneWidget,
    );
  });

  testWidgets('add catalogue is an outlined action, not a Material FAB', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(OutlinedButton, 'Add catalogue'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('library button asks for a folder when none is set', (
    tester,
  ) async {
    final notifier = FakeSettingsNotifier();
    final router = _makeRouter();
    await tester.pumpWidget(
      buildApp(router: router, settingsNotifier: notifier),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage local library'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a library folder'), findsOneWidget);
    expect(find.text('LIBRARY'), findsNothing);
  });

  testWidgets('library button opens the library once a folder is picked', (
    tester,
  ) async {
    final notifier = FakeSettingsNotifier();
    final router = _makeRouter();
    await tester.pumpWidget(
      buildApp(router: router, settingsNotifier: notifier),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage local library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();

    expect(notifier.pickCalls, 1);
    expect(find.text('LIBRARY'), findsOneWidget);
  });

  testWidgets(
    'library button opens the library directly when a folder is set',
    (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(
          target: CustomSafFolder('content://example', 'Folder'),
        ),
      );
      final router = _makeRouter();
      await tester.pumpWidget(
        buildApp(router: router, settingsNotifier: notifier),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Manage local library'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a library folder'), findsNothing);
      expect(find.text('LIBRARY'), findsOneWidget);
    },
  );

  /// Both section headers draw the same rule; only the favourites one tints it,
  /// to match its accented label. Neither carries a weight of its own.
  group('the section header rules', () {
    LinearGradient ruleUnder(WidgetTester tester, String label) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Row))
              .first,
          matching: find.descendant(
            of: find.byType(FadingRule),
            matching: find.byType(Container),
          ),
        ),
      );
      return (container.decoration! as BoxDecoration).gradient!
          as LinearGradient;
    }

    testWidgets('the catalogues rule is the shared one, not a third weight', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(catalogs: [_gutenberg], favorites: [_science]),
      );
      await tester.pumpAndSettle();

      expect(
        ruleUnder(tester, 'CATALOGUES').colors.first,
        buildLightTheme().extension<AppPalette>()!.rule,
      );
    });

    testWidgets('the favourites rule keeps its accent tint', (tester) async {
      await tester.pumpWidget(
        buildApp(catalogs: [_gutenberg], favorites: [_science]),
      );
      await tester.pumpAndSettle();

      final accent = buildLightTheme().colorScheme.primary.withValues(
        alpha: 0.35,
      );
      expect(ruleUnder(tester, 'FAVOURITES').colors.first, accent);
    });

    testWidgets('a header rule is anchored at its label and fades away', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(catalogs: [_gutenberg], favorites: [_science]),
      );
      await tester.pumpAndSettle();

      final gradient = ruleUnder(tester, 'CATALOGUES');
      expect(gradient.colors.first.a, greaterThan(0));
      expect(gradient.colors.last.a, 0);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class FakeFeedRepository implements FeedRepository {
  final CachedFeed initialFeed;
  final CachedFeed? refreshFeed;
  bool forceRefreshCalled = false;

  FakeFeedRepository({required this.initialFeed, this.refreshFeed});

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      forceRefreshCalled = true;
      if (refreshFeed != null) return refreshFeed!;
      throw Exception('network error');
    }
    return initialFeed;
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

  List<Favorite> get favorites => List.unmodifiable(_data);

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

// ── Helpers ──────────────────────────────────────────────────────────────────

class _FolderJobStub extends FolderDownloadNotifier {
  _FolderJobStub(this._state);
  final FolderJobState _state;
  @override
  FolderJobState build() => _state;
}

final _feedUrl = Uri.parse('http://example.com/feed');

CachedFeed makeFeed({
  String title = 'Test Feed',
  List<FeedEntry> entries = const [],
  DateTime? fetchedAt,
}) => CachedFeed(
  feed: ParsedFeed(title: title, entries: entries),
  fetchedAt: fetchedAt ?? DateTime(2026, 6, 13, 10, 0, 0),
  fromCache: true,
);

NavigationEntry navEntry({
  String title = 'Sub Folder',
  String? subtitle,
  String url = 'http://example.com/sub',
}) => NavigationEntry(title: title, subtitle: subtitle, url: Uri.parse(url));

BookEntry bookEntry({
  String title = 'My Book',
  List<String> authors = const ['Jane Doe'],
  String? series,
  double? seriesIndex,
}) => BookEntry(
  title: title,
  authors: authors,
  series: series,
  seriesIndex: seriesIndex,
  acquisitionLinks: [
    AcquisitionLink(
      url: Uri.parse('http://example.com/book.fb2'),
      mimeType: 'application/fb2',
      formatLabel: 'FB2',
    ),
  ],
);

Widget buildApp({
  required CachedFeed feed,
  List<Favorite> favorites = const [],
  CachedFeed? refreshFeed,
  int catalogId = 1,
  Uri? url,
  String? navTitle,
  String? navSubtitle,
  void Function(GoRouterState)? onBrowse,
  FolderJobState folderJobState = const FolderJobIdle(),
}) {
  final feedRepo = FakeFeedRepository(
    initialFeed: feed,
    refreshFeed: refreshFeed,
  );
  final favRepo = FakeFavoritesRepository(initial: favorites);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => BrowseScreen(
          catalogId: catalogId,
          url: url ?? _feedUrl,
          navTitle: navTitle,
          navSubtitle: navSubtitle,
        ),
      ),
      GoRoute(
        path: '/browse',
        builder: (_, state) {
          onBrowse?.call(state);
          return const Scaffold(body: Text('sub'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      feedRepositoryProvider.overrideWithValue(feedRepo),
      favoritesRepositoryProvider.overrideWithValue(favRepo),
      folderDownloadProvider.overrideWith(() => _FolderJobStub(folderJobState)),
    ],
    child: MaterialApp.router(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
    ),
  );
}

Widget buildAppWithDownload({
  required CachedFeed feed,
  int catalogId = 1,
  Uri? url,
}) {
  final feedRepo = FakeFeedRepository(initialFeed: feed);
  final favRepo = FakeFavoritesRepository();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            BrowseScreen(catalogId: catalogId, url: url ?? _feedUrl),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      feedRepositoryProvider.overrideWithValue(feedRepo),
      favoritesRepositoryProvider.overrideWithValue(favRepo),
      httpClientProvider.overrideWith(
        (ref) => MockClient((_) async => http.Response.bytes([1], 200)),
      ),
      downloadStorageProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp.router(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings;
  _FakeSettingsRepository(this._settings);
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

/// A browse screen whose debug panel is driven by a persisted [debugMode].
Widget buildAppWithDebugMode({
  required bool debugMode,
  required Uri url,
  String? inferredSeries,
}) {
  final feedRepo = FakeFeedRepository(initialFeed: makeFeed());
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => BrowseScreen(
          catalogId: 1,
          url: url,
          inferredSeries: inferredSeries,
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      feedRepositoryProvider.overrideWithValue(feedRepo),
      favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
      folderDownloadProvider.overrideWith(
        () => _FolderJobStub(const FolderJobIdle()),
      ),
      settingsRepositoryProvider.overrideWithValue(
        _FakeSettingsRepository(AppSettings(debugMode: debugMode)),
      ),
      safPermissionCheckerProvider.overrideWithValue((_) async => true),
    ],
    child: MaterialApp.router(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('renders feed title when cache exists', (tester) async {
    await tester.pumpWidget(buildApp(feed: makeFeed(title: 'My Library')));
    await tester.pumpAndSettle();

    expect(find.text('My Library'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('header names the folder that led here', (tester) async {
    await tester.pumpWidget(
      buildApp(
        feed: makeFeed(title: 'Authors'),
        navTitle: 'DI~',
        navSubtitle: '2515 authors',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DI~ · 2515 authors'), findsOneWidget);
  });

  testWidgets('header carries no context line at the root of a catalogue', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(feed: makeFeed(title: 'Authors')));
    await tester.pumpAndSettle();

    expect(find.text('Authors'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
  });

  testWidgets('the fetch time is gone from the header', (tester) async {
    await tester.pumpWidget(buildApp(feed: makeFeed()));
    await tester.pumpAndSettle();

    expect(find.textContaining('ago'), findsNothing);
  });

  testWidgets('entry list is inset above the system navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: buildApp(feed: makeFeed()),
      ),
    );
    await tester.pumpAndSettle();

    final scrollBottom = tester.getRect(find.byType(CustomScrollView)).bottom;
    expect(scrollBottom, lessThanOrEqualTo(600 - 48));
  });

  testWidgets('empty feed shows hint text', (tester) async {
    await tester.pumpWidget(buildApp(feed: makeFeed(entries: [])));
    await tester.pumpAndSettle();

    expect(find.text('This folder is empty.'), findsOneWidget);
  });

  testWidgets('initial load error shows error text and Retry button', (
    tester,
  ) async {
    // Use a FakeFeedRepository that always throws on first call.
    final feedRepo = _ThrowingFeedRepository();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BrowseScreen(catalogId: 1, url: _feedUrl),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(feedRepo),
          favoritesRepositoryProvider.overrideWithValue(
            FakeFavoritesRepository(),
          ),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Error'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('navigation entry renders its title with no folder icon', (
    tester,
  ) async {
    final feed = makeFeed(entries: [navEntry(title: 'Sub Folder')]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Sub Folder'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsNothing);
  });

  testWidgets('a navigation subtitle reads as one phrase', (tester) async {
    final feed = makeFeed(
      entries: [navEntry(title: 'DIC~', subtitle: '930 authors')],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('930 authors'), findsOneWidget);
  });

  testWidgets('a navigation subtitle sits on its own line under the title', (
    tester,
  ) async {
    final feed = makeFeed(
      entries: [
        navEntry(
          title: 'Series: The Warden',
          subtitle: '1 book by this author',
        ),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Series: The Warden'));
    final meta = tester.getRect(find.text('1 book by this author'));

    expect(meta.top, greaterThanOrEqualTo(title.bottom));
    expect(meta.left, closeTo(title.left, 0.5));
  });

  testWidgets('a long subtitle is laid out full width, not in a column', (
    tester,
  ) async {
    // Regression: the unit used to live in a fixed 52px column, so anything
    // longer than "books" was ellipsised down to "книга п…".
    final feed = makeFeed(
      entries: [navEntry(title: 'DIC~', subtitle: '25 books by this author')],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    final row = tester.getRect(find.byType(CustomScrollView));
    final meta = tester.getRect(find.text('25 books by this author'));

    expect(meta.width, greaterThan(52));
    expect(meta.right, lessThanOrEqualTo(row.right));
  });

  testWidgets('a subtitle with no count is shown whole', (tester) async {
    // Book rows carry the author as their subtitle — no leading number, so
    // the whole name used to be squeezed into the count column.
    final feed = makeFeed(
      entries: [navEntry(title: 'Vera (fb2)', subtitle: 'Dickens, Charles')],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Dickens, Charles'), findsOneWidget);
    expect(
      tester.getSize(find.text('Dickens, Charles')).width,
      greaterThan(52),
    );
  });

  testWidgets('a prefix bucket is set apart from a real entry', (tester) async {
    final feed = makeFeed(
      entries: [
        navEntry(title: 'DIC~', url: 'http://example.com/a'),
        navEntry(title: 'Dickens, Charles', url: 'http://example.com/b'),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    final palette = buildLightTheme().extension<AppPalette>()!;
    expect(
      tester.widget<Text>(find.text('DIC~')).style?.color,
      palette.bucketLabel,
    );
    expect(
      tester.widget<Text>(find.text('Dickens, Charles')).style?.color,
      isNot(palette.bucketLabel),
    );
  });

  testWidgets('"Entries only" hides the prefix buckets', (tester) async {
    final feed = makeFeed(
      entries: [
        navEntry(title: 'DIC~', url: 'http://example.com/a'),
        navEntry(title: 'Dickens, Charles', url: 'http://example.com/b'),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entries only'));
    await tester.pumpAndSettle();

    expect(find.text('DIC~'), findsNothing);
    expect(find.text('Dickens, Charles'), findsOneWidget);
  });

  testWidgets('"All" brings the hidden buckets back', (tester) async {
    final feed = makeFeed(entries: [navEntry(title: 'DIC~')]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entries only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('DIC~'), findsOneWidget);
  });

  testWidgets('Search opens a field that narrows the list', (tester) async {
    final feed = makeFeed(
      entries: [
        navEntry(title: 'Dickens, Charles', url: 'http://example.com/a'),
        navEntry(title: 'Trollope, Anthony', url: 'http://example.com/b'),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dickens');
    await tester.pumpAndSettle();

    expect(find.text('Dickens, Charles'), findsOneWidget);
    expect(find.text('Trollope, Anthony'), findsNothing);
  });

  testWidgets('closing Search clears the query and restores the list', (
    tester,
  ) async {
    final feed = makeFeed(
      entries: [
        navEntry(title: 'Dickens, Charles', url: 'http://example.com/a'),
        navEntry(title: 'Trollope, Anthony', url: 'http://example.com/b'),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dickens');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Trollope, Anthony'), findsOneWidget);
  });

  testWidgets('navigation entry renders subtitle when present', (tester) async {
    final feed = makeFeed(
      entries: [navEntry(title: 'Science', subtitle: 'Physics and more')],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsOneWidget);
    expect(find.text('Physics and more'), findsOneWidget);
  });

  testWidgets('book entry renders title and author', (tester) async {
    final feed = makeFeed(
      entries: [
        bookEntry(title: 'Dune', authors: ['Frank Herbert']),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Frank Herbert'), findsOneWidget);
    // No cover URL → placeholder book icon
    expect(find.byIcon(Icons.book), findsOneWidget);
  });

  testWidgets('book entry renders series line when present', (tester) async {
    final feed = makeFeed(
      entries: [
        bookEntry(title: 'Dune', series: 'Dune Chronicles', seriesIndex: 1),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Dune Chronicles #1'), findsOneWidget);
  });

  testWidgets('book entry with authors and no series sets isThreeLine true', (
    tester,
  ) async {
    final feed = makeFeed(
      entries: [
        bookEntry(title: 'Dune', authors: ['Frank Herbert']),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.isThreeLine, isTrue);
  });

  testWidgets('book entry shows download icon button', (tester) async {
    final feed = makeFeed(entries: [bookEntry(title: 'My Book')]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('tapping book row download button triggers download', (
    tester,
  ) async {
    final feed = makeFeed(entries: [bookEntry(title: 'My Book')]);
    await tester.pumpWidget(buildAppWithDownload(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('Download failed'), findsOneWidget);
  });

  testWidgets('mixed feed preserves entry order', (tester) async {
    final feed = makeFeed(
      entries: [
        navEntry(title: 'Folder A'),
        bookEntry(title: 'Book B'),
        navEntry(title: 'Folder C'),
      ],
    );
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    // Folder A first, Book B second, Folder C third — verify by text position.
    final folderA = tester.getTopLeft(find.text('Folder A'));
    final bookB = tester.getTopLeft(find.text('Book B'));
    final folderC = tester.getTopLeft(find.text('Folder C'));
    expect(folderA.dy < bookB.dy, true);
    expect(bookB.dy < folderC.dy, true);
  });

  testWidgets('refresh keeps content visible while loading', (tester) async {
    final initial = makeFeed(title: 'Initial');
    // refreshFeed=null → throws; we just need to see isRefreshing=true
    // Use a slow fake that never resolves to catch mid-refresh state.
    final slowRepo = _SlowFeedRepository(initialFeed: initial);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, s) => BrowseScreen(catalogId: 1, url: _feedUrl),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(slowRepo),
          favoritesRepositoryProvider.overrideWithValue(
            FakeFavoritesRepository(),
          ),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger refresh — do NOT await (we want mid-refresh state)
    final refreshIcon = find.byIcon(Icons.refresh);
    await tester.tap(refreshIcon);
    await tester.pump(); // one frame — refresh in progress

    // Old content still visible
    expect(find.text('Initial'), findsOneWidget);
    // Progress indicator visible
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let refresh complete
    slowRepo.complete(makeFeed(title: 'Refreshed'));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('refresh failure shows snackbar and keeps old content', (
    tester,
  ) async {
    final initial = makeFeed(title: 'Initial');
    // refreshFeed=null → throws on forceRefresh
    await tester.pumpWidget(buildApp(feed: initial, refreshFeed: null));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    // Old content preserved
    expect(find.text('Initial'), findsOneWidget);
    // Snackbar shown
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Refresh failed'), findsOneWidget);
  });

  testWidgets('star icon is unfilled when URL is not a favorite', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(feed: makeFeed(), favorites: []));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('star icon is filled when URL is a favorite', (tester) async {
    final fav = Favorite(
      id: 1,
      catalogId: 1,
      url: _feedUrl,
      title: 'Test Feed',
      sortOrder: 0,
    );
    await tester.pumpWidget(buildApp(feed: makeFeed(), favorites: [fav]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  testWidgets('tapping star when not favorited adds to favorites', (
    tester,
  ) async {
    // Use a repo we can inspect afterward.
    final favRepo = FakeFavoritesRepository();
    final feedRepo = FakeFeedRepository(initialFeed: makeFeed());
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BrowseScreen(catalogId: 1, url: _feedUrl),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(feedRepo),
          favoritesRepositoryProvider.overrideWithValue(favRepo),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(favRepo.favorites, hasLength(1));
    expect(favRepo.favorites.first.url, _feedUrl);
  });

  testWidgets('tapping a book entry tile opens BookDetailsSheet', (
    tester,
  ) async {
    final feed = makeFeed(entries: [bookEntry(title: 'My Book')]);
    await tester.pumpWidget(buildAppWithDownload(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Book'));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailsSheet), findsOneWidget);
  });

  testWidgets(
    'tapping navigation entry pushes /browse with catalogId, url, and title',
    (tester) async {
      final subUrl = 'http://example.com/sub';
      final feed = makeFeed(
        entries: [navEntry(title: 'Sub Folder', url: subUrl)],
      );

      String? capturedUri;
      await tester.pumpWidget(
        buildApp(
          feed: feed,
          catalogId: 1,
          onBrowse: (state) => capturedUri = state.uri.toString(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sub Folder'));
      await tester.pumpAndSettle();

      expect(capturedUri, isNotNull);
      expect(capturedUri, contains('catalogId=1'));
      expect(capturedUri, contains(Uri.encodeComponent(subUrl)));
      expect(capturedUri, contains(Uri.encodeComponent('Sub Folder')));
    },
  );

  testWidgets('tapping star uses navTitle as bookmark title when provided', (
    tester,
  ) async {
    final favRepo = FakeFavoritesRepository();
    final feedRepo = FakeFeedRepository(
      initialFeed: makeFeed(title: 'Feed Title'),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BrowseScreen(
            catalogId: 1,
            url: _feedUrl,
            navTitle: 'Nav Entry Title',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(feedRepo),
          favoritesRepositoryProvider.overrideWithValue(favRepo),
          folderDownloadProvider.overrideWith(
            () => _FolderJobStub(const FolderJobIdle()),
          ),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(favRepo.favorites, hasLength(1));
    expect(favRepo.favorites.first.title, 'Nav Entry Title');
  });

  testWidgets('tapping star uses feed title when navTitle is not provided', (
    tester,
  ) async {
    final favRepo = FakeFavoritesRepository();
    final feedRepo = FakeFeedRepository(
      initialFeed: makeFeed(title: 'Feed Title'),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BrowseScreen(catalogId: 1, url: _feedUrl),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(feedRepo),
          favoritesRepositoryProvider.overrideWithValue(favRepo),
          folderDownloadProvider.overrideWith(
            () => _FolderJobStub(const FolderJobIdle()),
          ),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(favRepo.favorites, hasLength(1));
    expect(favRepo.favorites.first.title, 'Feed Title');
  });

  testWidgets(
    'BrowseScreen with inferredSeries param shows series on book tiles when URL has no series',
    (tester) async {
      // Simulates the book-folder page: URL has no series param, but the
      // parent series-list page propagated inferredSeries via the route.
      final bookPageUrl = Uri.parse('http://example.com/book?uid=abc123');
      final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => BrowseScreen(
              catalogId: 1,
              url: bookPageUrl,
              inferredSeries: 'Dune Chronicles',
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(
              FakeFeedRepository(initialFeed: feed),
            ),
            favoritesRepositoryProvider.overrideWithValue(
              FakeFavoritesRepository(),
            ),
            folderDownloadProvider.overrideWith(
              () => _FolderJobStub(const FolderJobIdle()),
            ),
          ],
          child: MaterialApp.router(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Dune Chronicles'));
      expect(textWidget.style?.fontStyle, FontStyle.italic);
    },
  );

  testWidgets(
    'navigation tile push includes series param when inferredSeries is non-null',
    (tester) async {
      // When on a series page, tapping a nav entry should carry inferredSeries
      // into the child route so book tiles on the child page inherit it.
      final seriesUrl = Uri.parse(
        'http://example.com/feed?series=Dune+Chronicles',
      );
      final feed = makeFeed(entries: [navEntry(title: 'Book Folder')]);

      String? capturedUri;
      await tester.pumpWidget(
        buildApp(
          feed: feed,
          catalogId: 1,
          url: seriesUrl,
          onBrowse: (state) => capturedUri = state.uri.toString(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Book Folder'));
      await tester.pumpAndSettle();

      expect(capturedUri, isNotNull);
      expect(capturedUri, contains('series='));
      expect(capturedUri, contains('Dune'));
    },
  );

  testWidgets(
    'navigation tile push omits series param when inferredSeries is null',
    (tester) async {
      final feed = makeFeed(entries: [navEntry(title: 'Folder')]);

      String? capturedUri;
      await tester.pumpWidget(
        buildApp(
          feed: feed,
          catalogId: 1,
          onBrowse: (state) => capturedUri = state.uri.toString(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Folder'));
      await tester.pumpAndSettle();

      expect(capturedUri, isNotNull);
      expect(capturedUri, isNot(contains('series=')));
    },
  );

  testWidgets(
    'book with no series shows inferred series in italics when URL has series param',
    (tester) async {
      final seriesUrl = Uri.parse(
        'http://example.com/feed?series=Dune+Chronicles',
      );
      final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
      await tester.pumpWidget(buildApp(feed: feed, url: seriesUrl));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Dune Chronicles'));
      expect(textWidget.style?.fontStyle, FontStyle.italic);
    },
  );

  testWidgets(
    'book with own series uses real series — not italic, URL series ignored',
    (tester) async {
      final seriesUrl = Uri.parse('http://example.com/feed?series=URL+Series');
      final feed = makeFeed(
        entries: [
          bookEntry(title: 'Dune', series: 'Real Series', seriesIndex: 1),
        ],
      );
      await tester.pumpWidget(buildApp(feed: feed, url: seriesUrl));
      await tester.pumpAndSettle();

      expect(find.text('Real Series #1'), findsOneWidget);
      expect(find.text('URL Series'), findsNothing);
      final textWidget = tester.widget<Text>(find.text('Real Series #1'));
      expect(textWidget.style?.fontStyle, isNot(FontStyle.italic));
    },
  );

  testWidgets(
    'book with no series and no URL series param shows empty series area',
    (tester) async {
      final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
      await tester.pumpWidget(buildApp(feed: feed));
      await tester.pumpAndSettle();

      expect(find.text('Dune'), findsOneWidget);
      // No unexpected series text visible
      expect(find.text('Dune Chronicles'), findsNothing);
    },
  );

  group('Download-folder button', () {
    testWidgets('button enabled when FolderJobIdle', (tester) async {
      await tester.pumpWidget(
        buildApp(feed: makeFeed(), folderJobState: const FolderJobIdle()),
      );
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('button disabled during FolderJobScanning', (tester) async {
      await tester.pumpWidget(
        buildApp(
          feed: makeFeed(),
          folderJobState: const FolderJobScanning(foldersFound: 1),
        ),
      );
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('tapping button navigates to /folder-scan', (tester) async {
      String? pushedRoute;
      final feedRepo = FakeFeedRepository(initialFeed: makeFeed());
      final favRepo = FakeFavoritesRepository();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => BrowseScreen(catalogId: 1, url: _feedUrl),
          ),
          GoRoute(
            path: '/folder-scan',
            builder: (_, state) {
              pushedRoute = state.uri.toString();
              return const Scaffold(body: Text('scan'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(feedRepo),
            favoritesRepositoryProvider.overrideWithValue(favRepo),
            folderDownloadProvider.overrideWith(
              () => _FolderJobStub(const FolderJobIdle()),
            ),
          ],
          child: MaterialApp.router(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      await tester.pumpAndSettle();

      expect(pushedRoute, isNotNull);
      expect(pushedRoute, contains('catalogId=1'));
      expect(pushedRoute, contains(Uri.encodeComponent(_feedUrl.toString())));
    });

    testWidgets('button disabled when FolderJobDone', (tester) async {
      await tester.pumpWidget(
        buildApp(
          feed: makeFeed(),
          folderJobState: FolderJobDone(
            root: DownloadFolder(title: '', children: []),
            results: const {},
            wasCancelled: false,
            stoppedAtLimit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNull);
    });
  });

  group('debug panel', () {
    final debugUrl = Uri.parse('http://example.com/feed?q=abc');

    testWidgets('is hidden while debug mode is off', (tester) async {
      await tester.pumpWidget(
        buildAppWithDebugMode(debugMode: false, url: debugUrl),
      );
      await tester.pumpAndSettle();

      expect(find.text('/feed\nq=abc'), findsNothing);
    });

    testWidgets('shows the formatted URL while debug mode is on', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildAppWithDebugMode(debugMode: true, url: debugUrl),
      );
      await tester.pumpAndSettle();

      expect(find.text('/feed\nq=abc'), findsOneWidget);
    });

    testWidgets('does not show an inferred series row', (tester) async {
      await tester.pumpWidget(
        buildAppWithDebugMode(
          debugMode: true,
          url: debugUrl,
          inferredSeries: 'Great Series',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('series:'), findsNothing);
    });

    testWidgets('tapping it copies the full URL to the clipboard', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        buildAppWithDebugMode(debugMode: true, url: debugUrl),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('/feed\nq=abc'));
      await tester.pumpAndSettle();

      expect(copied, ['http://example.com/feed?q=abc']);
      expect(find.text('URL copied'), findsOneWidget);
    });
  });
}

class _ThrowingFeedRepository implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async => throw Exception('no connection');
}

class _SlowFeedRepository implements FeedRepository {
  final CachedFeed initialFeed;
  Completer<CachedFeed>? _refreshCompleter;

  _SlowFeedRepository({required this.initialFeed});

  void complete(CachedFeed feed) => _refreshCompleter?.complete(feed);

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      _refreshCompleter = Completer<CachedFeed>();
      return _refreshCompleter!.future;
    }
    return initialFeed;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
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

// ── Fakes ────────────────────────────────────────────────────────────────────

class FakeFeedRepository implements FeedRepository {
  final CachedFeed initialFeed;
  final CachedFeed? refreshFeed;
  bool forceRefreshCalled = false;

  FakeFeedRepository({required this.initialFeed, this.refreshFeed});

  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
      {bool forceRefresh = false}) async {
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
}) =>
    CachedFeed(
      feed: ParsedFeed(title: title, entries: entries),
      fetchedAt: fetchedAt ?? DateTime(2026, 6, 13, 10, 0, 0),
      fromCache: true,
    );

NavigationEntry navEntry({
  String title = 'Sub Folder',
  String? subtitle,
  String url = 'http://example.com/sub',
}) =>
    NavigationEntry(title: title, subtitle: subtitle, url: Uri.parse(url));

BookEntry bookEntry({
  String title = 'My Book',
  List<String> authors = const ['Jane Doe'],
  String? series,
  double? seriesIndex,
}) =>
    BookEntry(
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
  void Function(GoRouterState)? onBrowse,
  FolderJobState folderJobState = const FolderJobIdle(),
}) {
  final feedRepo =
      FakeFeedRepository(initialFeed: feed, refreshFeed: refreshFeed);
  final favRepo = FakeFavoritesRepository(initial: favorites);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => BrowseScreen(
          catalogId: catalogId,
          url: url ?? _feedUrl,
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
    child: MaterialApp.router(routerConfig: router),
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
    child: MaterialApp.router(routerConfig: router),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('renders feed title when cache exists', (tester) async {
    await tester.pumpWidget(buildApp(feed: makeFeed(title: 'My Library')));
    await tester.pumpAndSettle();

    expect(find.text('My Library'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows "Updated: X ago" subtitle', (tester) async {
    // fetchedAt = 2026-06-13 10:00:00; formatRelativeTime is pure so
    // we verify the subtitle widget exists (exact string may vary by clock).
    await tester.pumpWidget(buildApp(feed: makeFeed()));
    await tester.pumpAndSettle();

    // The subtitle is a Text inside the AppBar Column — check for "ago"
    expect(find.textContaining('ago'), findsOneWidget);
  });

  testWidgets('empty feed shows hint text', (tester) async {
    await tester.pumpWidget(buildApp(feed: makeFeed(entries: [])));
    await tester.pumpAndSettle();

    expect(find.text('This folder is empty.'), findsOneWidget);
  });

  testWidgets('initial load error shows error text and Retry button',
      (tester) async {
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feedRepo),
        favoritesRepositoryProvider
            .overrideWithValue(FakeFavoritesRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Error'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('navigation entry renders folder icon and title', (tester) async {
    final feed = makeFeed(entries: [navEntry(title: 'Sub Folder')]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.folder), findsOneWidget);
    expect(find.text('Sub Folder'), findsOneWidget);
  });

  testWidgets('navigation entry renders subtitle when present', (tester) async {
    final feed = makeFeed(
        entries: [navEntry(title: 'Science', subtitle: 'Physics and more')]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsOneWidget);
    expect(find.text('Physics and more'), findsOneWidget);
  });

  testWidgets('book entry renders title and author', (tester) async {
    final feed = makeFeed(
        entries: [bookEntry(title: 'Dune', authors: ['Frank Herbert'])]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Frank Herbert'), findsOneWidget);
    // No cover URL → placeholder book icon
    expect(find.byIcon(Icons.book), findsOneWidget);
  });

  testWidgets('book entry renders series line when present', (tester) async {
    final feed = makeFeed(entries: [
      bookEntry(title: 'Dune', series: 'Dune Chronicles', seriesIndex: 1)
    ]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Dune Chronicles #1'), findsOneWidget);
  });

  testWidgets('book entry with authors and no series sets isThreeLine true',
      (tester) async {
    final feed = makeFeed(entries: [
      bookEntry(title: 'Dune', authors: ['Frank Herbert']),
    ]);
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

  testWidgets('tapping book row download button triggers download',
      (tester) async {
    final feed = makeFeed(entries: [bookEntry(title: 'My Book')]);
    await tester.pumpWidget(buildAppWithDownload(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('Download failed'), findsOneWidget);
  });

  testWidgets('mixed feed preserves entry order', (tester) async {
    final feed = makeFeed(entries: [
      navEntry(title: 'Folder A'),
      bookEntry(title: 'Book B'),
      navEntry(title: 'Folder C'),
    ]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList(find.byType(ListTile)).toList();
    expect(tiles.length, 3);
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
          builder: (_, s) =>
              BrowseScreen(catalogId: 1, url: _feedUrl),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(slowRepo),
        favoritesRepositoryProvider
            .overrideWithValue(FakeFavoritesRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
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

  testWidgets('refresh failure shows snackbar and keeps old content',
      (tester) async {
    final initial = makeFeed(title: 'Initial');
    // refreshFeed=null → throws on forceRefresh
    await tester.pumpWidget(
        buildApp(feed: initial, refreshFeed: null));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    // Old content preserved
    expect(find.text('Initial'), findsOneWidget);
    // Snackbar shown
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Refresh failed'), findsOneWidget);
  });

  testWidgets('star icon is unfilled when URL is not a favorite', (tester) async {
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

  testWidgets('tapping star when not favorited adds to favorites', (tester) async {
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feedRepo),
        favoritesRepositoryProvider.overrideWithValue(favRepo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(favRepo.favorites, hasLength(1));
    expect(favRepo.favorites.first.url, _feedUrl);
  });

  testWidgets('tapping a book entry tile opens BookDetailsSheet', (tester) async {
    final feed = makeFeed(entries: [bookEntry(title: 'My Book')]);
    await tester.pumpWidget(buildAppWithDownload(feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Book'));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailsSheet), findsOneWidget);
  });

  testWidgets('tapping navigation entry pushes /browse with catalogId, url, and title',
      (tester) async {
    final subUrl = 'http://example.com/sub';
    final feed = makeFeed(entries: [navEntry(title: 'Sub Folder', url: subUrl)]);

    String? capturedUri;
    await tester.pumpWidget(buildApp(
      feed: feed,
      catalogId: 1,
      onBrowse: (state) => capturedUri = state.uri.toString(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sub Folder'));
    await tester.pumpAndSettle();

    expect(capturedUri, isNotNull);
    expect(capturedUri, contains('catalogId=1'));
    expect(capturedUri, contains(Uri.encodeComponent(subUrl)));
    expect(capturedUri, contains(Uri.encodeComponent('Sub Folder')));
  });

  testWidgets('tapping star uses navTitle as bookmark title when provided',
      (tester) async {
    final favRepo = FakeFavoritesRepository();
    final feedRepo =
        FakeFeedRepository(initialFeed: makeFeed(title: 'Feed Title'));
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feedRepo),
        favoritesRepositoryProvider.overrideWithValue(favRepo),
        folderDownloadProvider.overrideWith(() => _FolderJobStub(const FolderJobIdle())),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(favRepo.favorites, hasLength(1));
    expect(favRepo.favorites.first.title, 'Nav Entry Title');
  });

  testWidgets('tapping star uses feed title when navTitle is not provided',
      (tester) async {
    final favRepo = FakeFavoritesRepository();
    final feedRepo =
        FakeFeedRepository(initialFeed: makeFeed(title: 'Feed Title'));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BrowseScreen(catalogId: 1, url: _feedUrl),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feedRepo),
        favoritesRepositoryProvider.overrideWithValue(favRepo),
        folderDownloadProvider.overrideWith(() => _FolderJobStub(const FolderJobIdle())),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(favRepo.favorites, hasLength(1));
    expect(favRepo.favorites.first.title, 'Feed Title');
  });


  testWidgets('BrowseScreen with inferredSeries param shows series on book tiles when URL has no series',
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(
            FakeFeedRepository(initialFeed: feed)),
        favoritesRepositoryProvider
            .overrideWithValue(FakeFavoritesRepository()),
        folderDownloadProvider
            .overrideWith(() => _FolderJobStub(const FolderJobIdle())),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    final textWidget = tester.widget<Text>(find.text('Dune Chronicles'));
    expect(textWidget.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('navigation tile push includes series param when inferredSeries is non-null',
      (tester) async {
    // When on a series page, tapping a nav entry should carry inferredSeries
    // into the child route so book tiles on the child page inherit it.
    final seriesUrl = Uri.parse('http://example.com/feed?series=Dune+Chronicles');
    final feed = makeFeed(entries: [navEntry(title: 'Book Folder')]);

    String? capturedUri;
    await tester.pumpWidget(buildApp(
      feed: feed,
      catalogId: 1,
      url: seriesUrl,
      onBrowse: (state) => capturedUri = state.uri.toString(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Book Folder'));
    await tester.pumpAndSettle();

    expect(capturedUri, isNotNull);
    expect(capturedUri, contains('series='));
    expect(capturedUri, contains('Dune'));
  });

  testWidgets('navigation tile push omits series param when inferredSeries is null',
      (tester) async {
    final feed = makeFeed(entries: [navEntry(title: 'Folder')]);

    String? capturedUri;
    await tester.pumpWidget(buildApp(
      feed: feed,
      catalogId: 1,
      onBrowse: (state) => capturedUri = state.uri.toString(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();

    expect(capturedUri, isNotNull);
    expect(capturedUri, isNot(contains('series=')));
  });

  testWidgets('book with no series shows inferred series in italics when URL has series param',
      (tester) async {
    final seriesUrl = Uri.parse('http://example.com/feed?series=Dune+Chronicles');
    final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
    await tester.pumpWidget(buildApp(feed: feed, url: seriesUrl));
    await tester.pumpAndSettle();

    final textWidget = tester.widget<Text>(find.text('Dune Chronicles'));
    expect(textWidget.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('book with own series uses real series — not italic, URL series ignored',
      (tester) async {
    final seriesUrl = Uri.parse('http://example.com/feed?series=URL+Series');
    final feed = makeFeed(
        entries: [bookEntry(title: 'Dune', series: 'Real Series', seriesIndex: 1)]);
    await tester.pumpWidget(buildApp(feed: feed, url: seriesUrl));
    await tester.pumpAndSettle();

    expect(find.text('Real Series #1'), findsOneWidget);
    expect(find.text('URL Series'), findsNothing);
    final textWidget = tester.widget<Text>(find.text('Real Series #1'));
    expect(textWidget.style?.fontStyle, isNot(FontStyle.italic));
  });

  testWidgets('book with no series and no URL series param shows empty series area',
      (tester) async {
    final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
    await tester.pumpWidget(buildApp(feed: feed));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    // No unexpected series text visible
    expect(find.text('Dune Chronicles'), findsNothing);
  });

  group('Download-folder button', () {
    testWidgets('button enabled when FolderJobIdle', (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobIdle(),
      ));
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('button disabled during FolderJobScanning', (tester) async {
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: const FolderJobScanning(foldersFound: 1),
      ));
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
      await tester.pumpWidget(ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(feedRepo),
          favoritesRepositoryProvider.overrideWithValue(favRepo),
          folderDownloadProvider
              .overrideWith(() => _FolderJobStub(const FolderJobIdle())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
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
      await tester.pumpWidget(buildApp(
        feed: makeFeed(),
        folderJobState: FolderJobDone(
          root: DownloadFolder(title: '', children: []),
          results: const {},
          wasCancelled: false,
          stoppedAtLimit: false,
        ),
      ));
      await tester.pumpAndSettle();
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_for_offline_outlined),
      );
      expect(btn.onPressed, isNull);
    });
  });
}

class _ThrowingFeedRepository implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
          {bool forceRefresh = false}) async =>
      throw Exception('no connection');
}

class _SlowFeedRepository implements FeedRepository {
  final CachedFeed initialFeed;
  Completer<CachedFeed>? _refreshCompleter;

  _SlowFeedRepository({required this.initialFeed});

  void complete(CachedFeed feed) => _refreshCompleter?.complete(feed);

  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
      {bool forceRefresh = false}) async {
    if (forceRefresh) {
      _refreshCompleter = Completer<CachedFeed>();
      return _refreshCompleter!.future;
    }
    return initialFeed;
  }
}

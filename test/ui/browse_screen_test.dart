import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
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
}

class _ThrowingFeedRepository implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
          {bool forceRefresh = false}) async =>
      throw Exception('no connection');
}

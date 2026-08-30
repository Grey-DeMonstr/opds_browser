import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/search_screen.dart';
import 'package:opds_browser/ui/theme.dart';

final rootUrl = Uri.parse('https://example.com/opds');

final searchLink = SearchLink(
  url: Uri.parse('https://example.com/s?q={searchTerms}'),
  type: 'application/atom+xml',
);

class FakeRootRepository implements FeedRepository {
  final List<SearchLink> searchLinks;
  FakeRootRepository({this.searchLinks = const []});

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async => CachedFeed(
    feed: ParsedFeed(
      title: 'Example',
      entries: const [],
      searchLinks: searchLinks,
    ),
    fetchedAt: DateTime(2026, 8, 30),
    fromCache: true,
  );
}

class FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<Catalog>> getAll() async => [
    Catalog(id: 1, title: 'Example', rootUrl: rootUrl, protocol: 'opds1'),
  ];

  @override
  Future<Catalog> add(String t, Uri u) async => throw UnimplementedError();
  @override
  Future<void> update(Catalog c) async => throw UnimplementedError();
  @override
  Future<void> delete(int id) async => throw UnimplementedError();
}

class FakeClient implements OpdsClient {
  final Map<String, ParsedFeed> pages;
  final Map<String, Completer<void>> gates;

  FakeClient({this.pages = const {}, this.gates = const {}});

  @override
  Future<ParsedFeed> fetchFeed(Uri url) async {
    final gate = gates[url.toString()];
    if (gate != null) await gate.future;
    final page = pages[url.toString()];
    if (page == null) throw const NetworkException('unreachable');
    return page;
  }

  @override
  Future<bool> probe(Uri url) async => true;

  @override
  Future<String?> resolveSearchTemplate(SearchLink link) async =>
      'https://example.com/s?q={searchTerms}';
}

BookEntry book(String title) => BookEntry(
  title: title,
  authors: const ['Someone'],
  acquisitionLinks: [
    AcquisitionLink(
      url: Uri.parse('https://example.com/b.fb2'),
      mimeType: 'application/fb2',
      formatLabel: 'FB2',
    ),
  ],
);

Widget buildApp({
  required FakeClient client,
  List<SearchLink> rootLinks = const [],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => SearchScreen(catalogId: 1, rootUrl: rootUrl),
      ),
      GoRoute(
        path: '/browse',
        builder: (_, _) => const Scaffold(body: Text('browse')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      opdsClientProvider.overrideWithValue(client),
      feedRepositoryProvider.overrideWithValue(
        FakeRootRepository(searchLinks: rootLinks),
      ),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      searchPageDelayProvider.overrideWithValue(Duration.zero),
    ],
    child: MaterialApp.router(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
    ),
  );
}

Future<void> runQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the field names what a query will match', (tester) async {
    await tester.pumpWidget(buildApp(client: FakeClient()));
    await tester.pumpAndSettle();

    expect(find.text('Title, author or series'), findsOneWidget);
  });

  testWidgets('the screen says the scope is the whole catalogue', (
    tester,
  ) async {
    // The one thing this screen exists to make plain: it is not the folder
    // you came from.
    await tester.pumpWidget(buildApp(client: FakeClient()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Searches all of Example'), findsOneWidget);
    expect(find.textContaining('not the folder you came from'), findsOneWidget);
  });

  testWidgets('results are listed and the header counts what arrived', (
    tester,
  ) async {
    final client = FakeClient(
      pages: {
        'https://example.com/s?q=witch': ParsedFeed(
          title: 'Search',
          entries: [book('A Witch Abroad'), book('Witch Week')],
        ),
      },
    );
    await tester.pumpWidget(buildApp(client: client, rootLinks: [searchLink]));
    await tester.pumpAndSettle();
    await runQuery(tester, 'witch');

    expect(find.text('A Witch Abroad'), findsOneWidget);
    expect(find.text('Witch Week'), findsOneWidget);
    expect(find.text('Example · 2 loaded · page 1'), findsOneWidget);
  });

  testWidgets('an unpaginated result offers no footer to continue from', (
    tester,
  ) async {
    // The reference catalogue answers in one capped page. Offering Continue
    // would promise a page that does not exist.
    final client = FakeClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [book('Only One')],
        ),
      },
    );
    await tester.pumpWidget(buildApp(client: client, rootLinks: [searchLink]));
    await tester.pumpAndSettle();
    await runQuery(tester, 'x');

    expect(find.text('Continue'), findsNothing);
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('a walk in flight names the page it is fetching, and stops', (
    tester,
  ) async {
    final gate = Completer<void>();
    final client = FakeClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [book('First')],
          nextPageUrl: Uri.parse('https://example.com/s?q=x&p=2'),
        ),
        'https://example.com/s?q=x&p=2': ParsedFeed(
          title: 'Search',
          entries: [book('Second')],
        ),
      },
      gates: {'https://example.com/s?q=x&p=2': gate},
    );
    await tester.pumpWidget(buildApp(client: client, rootLinks: [searchLink]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Fetching page 2…'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(find.text('Stopped at page 1 of an unknown total'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a query matching nothing says so', (tester) async {
    final client = FakeClient(
      pages: {
        'https://example.com/s?q=zzz': const ParsedFeed(
          title: 'Search',
          entries: [],
        ),
      },
    );
    await tester.pumpWidget(buildApp(client: client, rootLinks: [searchLink]));
    await tester.pumpAndSettle();
    await runQuery(tester, 'zzz');

    expect(find.text('Nothing found for that.'), findsOneWidget);
  });

  testWidgets('a catalogue answering with a menu of scopes still works', (
    tester,
  ) async {
    // Some catalogues answer a query with navigation entries rather than
    // books. Rendering only books would make them look like they found none.
    final client = FakeClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [
            NavigationEntry(
              title: 'Search authors',
              url: Uri.parse('https://example.com/s?type=author&q=x'),
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(buildApp(client: client, rootLinks: [searchLink]));
    await tester.pumpAndSettle();
    await runQuery(tester, 'x');

    expect(find.text('Search authors'), findsOneWidget);
  });

  testWidgets('a failure is reported with a way to try again', (tester) async {
    await tester.pumpWidget(
      buildApp(client: FakeClient(), rootLinks: [searchLink]),
    );
    await tester.pumpAndSettle();
    await runQuery(tester, 'x');

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a catalogue offering no search says so rather than guessing', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(client: FakeClient()));
    await tester.pumpAndSettle();
    await runQuery(tester, 'x');

    expect(find.textContaining('does not offer a search'), findsOneWidget);
  });
}

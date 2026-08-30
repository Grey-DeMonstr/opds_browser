import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

/// Answers each URL from [pages], recording the order they were asked for.
class FakeSearchClient implements OpdsClient {
  final Map<String, ParsedFeed> pages;
  final String? template;
  final Object? throwOnFetch;
  final List<String> requested = [];

  /// Called as each page is served, so a test can act mid-walk.
  void Function(String url)? onFetch;

  FakeSearchClient({
    this.pages = const {},
    this.template = 'https://example.com/s?q={searchTerms}',
    this.throwOnFetch,
  });

  @override
  Future<ParsedFeed> fetchFeed(Uri url) async {
    requested.add(url.toString());
    onFetch?.call(url.toString());
    if (throwOnFetch != null) throw throwOnFetch!;
    final page = pages[url.toString()];
    if (page == null) throw ParseException('no page for $url');
    return page;
  }

  @override
  Future<bool> probe(Uri url) async => true;

  @override
  Future<String?> resolveSearchTemplate(SearchLink link) async => template;
}

/// Serves the catalogue root, carrying whatever search links the case needs.
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
      title: 'Root',
      entries: const [],
      searchLinks: searchLinks,
    ),
    fetchedAt: DateTime(2026, 8, 30),
    fromCache: true,
  );
}

final templateLink = SearchLink(
  url: Uri.parse('https://example.com/s?q={searchTerms}'),
  type: 'application/atom+xml',
);

BookEntry book(String title) => BookEntry(
  title: title,
  authors: const ['A'],
  acquisitionLinks: [
    AcquisitionLink(
      url: Uri.parse('https://example.com/$title.fb2'),
      mimeType: 'application/fb2',
      formatLabel: 'FB2',
    ),
  ],
);

void main() {
  final root = Uri.parse('https://example.com/opds');
  SearchArgs argsFor() => (1, root);

  ProviderContainer containerWith(
    FakeSearchClient client, {
    List<SearchLink>? rootLinks,
  }) {
    final c = ProviderContainer(
      overrides: [
        opdsClientProvider.overrideWithValue(client),
        feedRepositoryProvider.overrideWithValue(
          FakeRootRepository(searchLinks: rootLinks ?? [templateLink]),
        ),
        searchPageDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(c.dispose);
    // A screen watching the provider is what keeps an autoDispose family
    // alive across the walk's async gaps.
    c.listen(searchProvider(argsFor()), (_, _) {});
    return c;
  }

  test('a query with no results still finishes', () async {
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=nothing': const ParsedFeed(
          title: 'Search',
          entries: [],
        ),
      },
    );
    final c = containerWith(client);
    await c.read(searchProvider(argsFor()).notifier).search('nothing');

    final state = c.read(searchProvider(argsFor()));
    expect(state.status, SearchStatus.done);
    expect(state.entries, isEmpty);
    expect(state.pagesLoaded, 1);
  });

  test('pages are followed and their entries accumulate in order', () async {
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [book('one'), book('two')],
          nextPageUrl: Uri.parse('https://example.com/s?q=x&p=2'),
        ),
        'https://example.com/s?q=x&p=2': ParsedFeed(
          title: 'Search',
          entries: [book('three')],
        ),
      },
    );
    final c = containerWith(client);
    await c.read(searchProvider(argsFor()).notifier).search('x');

    final state = c.read(searchProvider(argsFor()));
    expect(state.entries.map((e) => (e as BookEntry).title), [
      'one',
      'two',
      'three',
    ]);
    expect(state.pagesLoaded, 2);
    expect(state.status, SearchStatus.done);
    expect(state.nextPageUrl, isNull);
  });

  test('a feed offering no next page is done after one request', () async {
    // The reference catalogue answers a query with a capped, unpaginated
    // feed. Nothing may sit waiting for a second page that never comes.
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [book('only')],
        ),
      },
    );
    final c = containerWith(client);
    await c.read(searchProvider(argsFor()).notifier).search('x');

    expect(c.read(searchProvider(argsFor())).status, SearchStatus.done);
    expect(client.requested, ['https://example.com/s?q=x']);
  });

  test('the query is trimmed and an empty one does nothing', () async {
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=x': const ParsedFeed(
          title: 'Search',
          entries: [],
        ),
      },
    );
    final c = containerWith(client);
    final notifier = c.read(searchProvider(argsFor()).notifier);

    await notifier.search('   ');
    expect(c.read(searchProvider(argsFor())).status, SearchStatus.idle);
    expect(client.requested, isEmpty);

    await notifier.search('  x  ');
    expect(c.read(searchProvider(argsFor())).query, 'x');
  });

  test(
    'a catalogue with no usable template reports it and asks nothing',
    () async {
      final client = FakeSearchClient(template: null);
      final c = containerWith(client);
      await c.read(searchProvider(argsFor()).notifier).search('x');

      final state = c.read(searchProvider(argsFor()));
      expect(state.status, SearchStatus.failed);
      expect(client.requested, isEmpty);
    },
  );

  test('a failed page leaves what already arrived on screen', () async {
    final client = FakeSearchClient(
      throwOnFetch: const NetworkException('down'),
    );
    final c = containerWith(client);
    await c.read(searchProvider(argsFor()).notifier).search('x');

    final state = c.read(searchProvider(argsFor()));
    expect(state.status, SearchStatus.failed);
    expect(state.error, isNotNull);
  });

  test('a page in flight when Stop is pressed is discarded', () async {
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [book('one')],
          nextPageUrl: Uri.parse('https://example.com/s?q=x&p=2'),
        ),
        'https://example.com/s?q=x&p=2': ParsedFeed(
          title: 'Search',
          entries: [book('two')],
        ),
      },
    );
    final c = containerWith(client);
    final notifier = c.read(searchProvider(argsFor()).notifier);

    // Stop while the second page is being served. Its rows must not land.
    client.onFetch = (url) {
      if (url.endsWith('p=2')) notifier.stop();
    };
    await notifier.search('x');

    final stopped = c.read(searchProvider(argsFor()));
    expect(stopped.status, SearchStatus.stopped);
    expect(stopped.entries.map((e) => (e as BookEntry).title), ['one']);
    expect(stopped.pagesLoaded, 1);
    expect(client.requested, [
      'https://example.com/s?q=x',
      'https://example.com/s?q=x&p=2',
    ]);
  });

  test('resume re-fetches the page the walk stopped on', () async {
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=x': ParsedFeed(
          title: 'Search',
          entries: [book('one')],
          nextPageUrl: Uri.parse('https://example.com/s?q=x&p=2'),
        ),
        'https://example.com/s?q=x&p=2': ParsedFeed(
          title: 'Search',
          entries: [book('two')],
        ),
      },
    );
    final c = containerWith(client);
    final notifier = c.read(searchProvider(argsFor()).notifier);

    client.onFetch = (url) {
      if (url.endsWith('p=2')) notifier.stop();
    };
    await notifier.search('x');

    client.onFetch = null;
    await notifier.resume();

    final resumed = c.read(searchProvider(argsFor()));
    expect(resumed.entries.map((e) => (e as BookEntry).title), ['one', 'two']);
    expect(resumed.status, SearchStatus.done);
    expect(resumed.pagesLoaded, 2);
  });

  test('a second query replaces the first rather than appending', () async {
    final client = FakeSearchClient(
      pages: {
        'https://example.com/s?q=one': ParsedFeed(
          title: 'Search',
          entries: [book('a')],
        ),
        'https://example.com/s?q=two': ParsedFeed(
          title: 'Search',
          entries: [book('b')],
        ),
      },
    );
    final c = containerWith(client);
    final notifier = c.read(searchProvider(argsFor()).notifier);

    await notifier.search('one');
    await notifier.search('two');

    final state = c.read(searchProvider(argsFor()));
    expect(state.query, 'two');
    expect(state.entries.map((e) => (e as BookEntry).title), ['b']);
    expect(state.pagesLoaded, 1);
  });

  test('the template is resolved once and reused across queries', () async {
    var resolved = 0;
    final client = _CountingClient(() => resolved++);
    final c = ProviderContainer(
      overrides: [
        opdsClientProvider.overrideWithValue(client),
        feedRepositoryProvider.overrideWithValue(
          FakeRootRepository(searchLinks: [templateLink]),
        ),
        searchPageDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(c.dispose);
    c.listen(searchProvider(argsFor()), (_, _) {});

    final notifier = c.read(searchProvider(argsFor()).notifier);
    await notifier.search('one');
    await notifier.search('two');

    expect(resolved, 1);
  });

  test('a root advertising no search never reaches the client', () async {
    final client = FakeSearchClient();
    final c = containerWith(client, rootLinks: const []);
    await c.read(searchProvider(argsFor()).notifier).search('x');

    final state = c.read(searchProvider(argsFor()));
    expect(state.status, SearchStatus.failed);
    expect(client.requested, isEmpty);
  });
}

class _CountingClient implements OpdsClient {
  final void Function() onResolve;
  _CountingClient(this.onResolve);

  @override
  Future<ParsedFeed> fetchFeed(Uri url) async =>
      const ParsedFeed(title: 'Search', entries: []);

  @override
  Future<bool> probe(Uri url) async => true;

  @override
  Future<String?> resolveSearchTemplate(SearchLink link) async {
    onResolve();
    return 'https://example.com/s?q={searchTerms}';
  }
}

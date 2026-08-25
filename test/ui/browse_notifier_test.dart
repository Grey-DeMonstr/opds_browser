import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/browse_list.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

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

/// A repository with a scripted answer for every URL, which records how the
/// browse screen went about asking for them.
class ScriptedFeedRepository implements FeedRepository {
  final CachedFeed root;
  final CachedFeed? refreshed;
  final Map<String, CachedFeed> probes;
  final Set<String> failing;

  /// When set, every probe waits for [release], so a test can stop the walk
  /// while a request is still in flight.
  final bool gated;

  final List<Uri> probed = [];
  int _inFlight = 0;
  int peakInFlight = 0;
  Completer<void>? _gate;

  ScriptedFeedRepository({
    required this.root,
    required this.probes,
    this.refreshed,
    this.failing = const {},
    this.gated = false,
  });

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async {
    if (url == Uri.parse('http://example.com/feed')) {
      return forceRefresh ? refreshed! : root;
    }

    probed.add(url);
    _inFlight++;
    if (_inFlight > peakInFlight) peakInFlight = _inFlight;
    try {
      if (gated) {
        _gate = Completer<void>();
        await _gate!.future;
      } else {
        // Yields, so a walk that ran its probes concurrently would show more
        // than one in flight here.
        await Future<void>.delayed(Duration.zero);
      }
      if (failing.contains(url.toString())) throw Exception('probe failed');
      final feed = probes[url.toString()];
      if (feed == null) throw StateError('no script for $url');
      return feed;
    } finally {
      _inFlight--;
    }
  }
}

void main() {
  final testUri = Uri.parse('http://example.com/feed');
  final testFeed = CachedFeed(
    feed: const ParsedFeed(title: 'Test', entries: []),
    fetchedAt: DateTime(2026, 6, 13),
    fromCache: true,
  );
  final (int, Uri) args = (1, testUri);

  ProviderContainer makeContainer(FakeFeedRepository repo) {
    final c = ProviderContainer(
      overrides: [feedRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('build() returns feed from repository', () async {
    final container = makeContainer(FakeFeedRepository(initialFeed: testFeed));
    // keep provider alive
    final sub = container.listen(browseProvider(args), (_, _) {});
    addTearDown(sub.close);

    final state = await container.read(browseProvider(args).future);
    expect(state.feed, testFeed);
    expect(state.isRefreshing, false);
  });

  test('refresh() updates feed via forceRefresh', () async {
    final updated = CachedFeed(
      feed: const ParsedFeed(title: 'Updated', entries: []),
      fetchedAt: DateTime(2026, 6, 13, 1),
      fromCache: false,
    );
    final repo = FakeFeedRepository(
      initialFeed: testFeed,
      refreshFeed: updated,
    );
    final container = makeContainer(repo);
    final sub = container.listen(browseProvider(args), (_, _) {});
    addTearDown(sub.close);

    await container.read(browseProvider(args).future);
    await container.read(browseProvider(args).notifier).refresh();

    final state = container.read(browseProvider(args)).value!;
    expect(state.feed, updated);
    expect(state.isRefreshing, false);
    expect(repo.forceRefreshCalled, true);
  });

  test('refresh() on failure preserves old feed and rethrows', () async {
    final repo = FakeFeedRepository(
      initialFeed: testFeed,
    ); // refreshFeed=null → throws
    final container = makeContainer(repo);
    final sub = container.listen(browseProvider(args), (_, _) {});
    addTearDown(sub.close);

    await container.read(browseProvider(args).future);

    await expectLater(
      container.read(browseProvider(args).notifier).refresh(),
      throwsA(isA<Exception>()),
    );

    final state = container.read(browseProvider(args)).value!;
    expect(state.feed, testFeed);
    expect(state.isRefreshing, false);
  });

  group('single-book folders resolve in the background', () {
    NavigationEntry wrapper(String title) => NavigationEntry(
      title: title,
      url: Uri.parse('http://example.com/book/$title'),
      linkType: 'application/atom+xml;profile=opds-catalog;kind=acquisition',
    );

    NavigationEntry folder(String title) => NavigationEntry(
      title: title,
      url: Uri.parse('http://example.com/series/$title'),
      linkType: 'application/atom+xml;profile=opds-catalog;kind=navigation',
    );

    BookEntry book(String title) => BookEntry(
      title: title,
      authors: const ['Olga Gromyko'],
      acquisitionLinks: [
        AcquisitionLink(
          url: Uri.parse('http://example.com/download/$title'),
          mimeType: 'application/fb2',
          formatLabel: 'FB2',
        ),
      ],
    );

    CachedFeed cached(List<FeedEntry> entries) => CachedFeed(
      feed: ParsedFeed(title: 'Feed', entries: entries),
      fetchedAt: DateTime(2026, 6, 13),
      fromCache: false,
    );

    ProviderContainer containerFor(ScriptedFeedRepository repo) {
      final c = ProviderContainer(
        overrides: [
          feedRepositoryProvider.overrideWithValue(repo),
          browseProbeDelayProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    List<FeedEntry> entriesOf(ProviderContainer c) =>
        c.read(browseProvider(args)).value!.feed.feed.entries;

    test('each wrapper becomes the book it holds, in place', () async {
      final repo = ScriptedFeedRepository(
        root: cached([
          wrapper('Stringy'),
          folder('Chronicles'),
          wrapper('Art'),
        ]),
        probes: {
          'http://example.com/book/Stringy': cached([book('Stringy')]),
          'http://example.com/book/Art': cached([book('Art')]),
        },
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});
      addTearDown(sub.close);

      await container.read(browseProvider(args).future);
      await pumpEventQueue();

      final entries = entriesOf(container);
      expect(entries[0], isA<BookEntry>());
      expect(entries[1], isA<NavigationEntry>());
      expect(entries[2], isA<BookEntry>());
      expect(entries.map(browseEntryTitle), ['Stringy', 'Chronicles', 'Art']);
    });

    test('navigation-kind folders are never fetched', () async {
      final repo = ScriptedFeedRepository(
        root: cached([folder('Chronicles'), folder('Anthology')]),
        probes: const {},
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});
      addTearDown(sub.close);

      await container.read(browseProvider(args).future);
      await pumpEventQueue();

      expect(repo.probed, isEmpty);
    });

    test('a wrapper holding two books keeps its row', () async {
      final repo = ScriptedFeedRepository(
        root: cached([wrapper('Chronicles')]),
        probes: {
          'http://example.com/book/Chronicles': cached([
            book('One'),
            book('Two'),
          ]),
        },
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});
      addTearDown(sub.close);

      await container.read(browseProvider(args).future);
      await pumpEventQueue();

      expect(entriesOf(container).single, isA<NavigationEntry>());
    });

    test('a failed probe leaves its row and the walk carries on', () async {
      final repo = ScriptedFeedRepository(
        root: cached([wrapper('Broken'), wrapper('Art')]),
        probes: {
          'http://example.com/book/Art': cached([book('Art')]),
        },
        failing: const {'http://example.com/book/Broken'},
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});
      addTearDown(sub.close);

      await container.read(browseProvider(args).future);
      await pumpEventQueue();

      final entries = entriesOf(container);
      expect(entries[0], isA<NavigationEntry>());
      expect(entries[1], isA<BookEntry>());
    });

    test('probes run one at a time, in list order', () async {
      final repo = ScriptedFeedRepository(
        root: cached([wrapper('A'), wrapper('B'), wrapper('C')]),
        probes: {
          'http://example.com/book/A': cached([book('A')]),
          'http://example.com/book/B': cached([book('B')]),
          'http://example.com/book/C': cached([book('C')]),
        },
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});
      addTearDown(sub.close);

      await container.read(browseProvider(args).future);
      await pumpEventQueue();

      expect(repo.peakInFlight, 1);
      expect(repo.probed, [
        Uri.parse('http://example.com/book/A'),
        Uri.parse('http://example.com/book/B'),
        Uri.parse('http://example.com/book/C'),
      ]);
    });

    test('leaving the screen stops the walk', () async {
      final repo = ScriptedFeedRepository(
        root: cached([wrapper('A'), wrapper('B')]),
        probes: {
          'http://example.com/book/A': cached([book('A')]),
          'http://example.com/book/B': cached([book('B')]),
        },
        gated: true,
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});

      await container.read(browseProvider(args).future);
      await pumpEventQueue();
      expect(repo.probed.length, 1);

      sub.close();
      await pumpEventQueue();
      repo.release();
      await pumpEventQueue();

      expect(repo.probed.length, 1);
    });

    test('refresh() walks the folders the new feed brought', () async {
      final repo = ScriptedFeedRepository(
        root: cached([folder('Chronicles')]),
        refreshed: cached([wrapper('Art')]),
        probes: {
          'http://example.com/book/Art': cached([book('Art')]),
        },
      );
      final container = containerFor(repo);
      final sub = container.listen(browseProvider(args), (_, _) {});
      addTearDown(sub.close);

      await container.read(browseProvider(args).future);
      await container.read(browseProvider(args).notifier).refresh();
      await pumpEventQueue();

      expect(entriesOf(container).single, isA<BookEntry>());
    });
  });
}

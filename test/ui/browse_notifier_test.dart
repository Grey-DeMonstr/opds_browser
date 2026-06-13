import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

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

void main() {
  final testUri = Uri.parse('http://example.com/feed');
  final testFeed = CachedFeed(
    feed: const ParsedFeed(title: 'Test', entries: []),
    fetchedAt: DateTime(2026, 6, 13),
    fromCache: true,
  );
  final (int, Uri) args = (1, testUri);

  ProviderContainer makeContainer(FakeFeedRepository repo) {
    final c = ProviderContainer(overrides: [
      feedRepositoryProvider.overrideWithValue(repo),
    ]);
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
    final repo = FakeFeedRepository(initialFeed: testFeed, refreshFeed: updated);
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
    final repo = FakeFeedRepository(initialFeed: testFeed); // refreshFeed=null → throws
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
}

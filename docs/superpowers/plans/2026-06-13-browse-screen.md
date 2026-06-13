# BrowseScreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement BrowseScreen with cache-first rendering, manual/pull-to-refresh (content stays visible during refresh), favorites toggle, and mixed navigation/book entry display.

**Architecture:** `BrowseNotifier extends AutoDisposeFamilyAsyncNotifier<BrowseState, (int, Uri)>` owns feed state per screen; `isFavoriteProvider` is a derived `Provider.autoDispose.family` reading from the global `favoritesProvider`; `BrowseScreen` is a `ConsumerStatefulWidget` so `_refresh()` can `await` and show a SnackBar after mounting; entry tiles are separate private `StatelessWidget` classes with `ValueKey`.

**Tech Stack:** Flutter, Riverpod 2.x (non-codegen `AsyncNotifier.family`, `autoDispose`), go_router (`context.push`), `cached_network_image`, `flutter_test`.

---

### Task 1: `formatRelativeTime` pure function

**Files:**
- Create: `lib/domain/time_formatter.dart`
- Create: `test/domain/time_formatter_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/domain/time_formatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/time_formatter.dart';

void main() {
  final now = DateTime(2026, 6, 13, 12, 0, 0);
  DateTime t(int secondsAgo) => now.subtract(Duration(seconds: secondsAgo));

  test('< 60 s → just now', () {
    expect(formatRelativeTime(t(0), now), 'just now');
    expect(formatRelativeTime(t(59), now), 'just now');
  });

  test('< 1 h → X minutes ago', () {
    expect(formatRelativeTime(t(60), now), '1 minutes ago');
    expect(formatRelativeTime(t(90), now), '1 minutes ago');
    expect(formatRelativeTime(t(3599), now), '59 minutes ago');
  });

  test('< 24 h → X hours ago', () {
    expect(formatRelativeTime(t(3600), now), '1 hours ago');
    expect(formatRelativeTime(t(7200), now), '2 hours ago');
    expect(formatRelativeTime(t(86399), now), '23 hours ago');
  });

  test('< 30 days → X days ago', () {
    expect(formatRelativeTime(t(86400), now), '1 days ago');
    expect(formatRelativeTime(t(86400 * 7), now), '7 days ago');
    expect(formatRelativeTime(t(86400 * 29), now), '29 days ago');
  });

  test('< 365 days → X months ago', () {
    expect(formatRelativeTime(t(86400 * 30), now), '1 months ago');
    expect(formatRelativeTime(t(86400 * 60), now), '2 months ago');
    expect(formatRelativeTime(t(86400 * 364), now), '12 months ago');
  });

  test('>= 365 days → X years ago', () {
    expect(formatRelativeTime(t(86400 * 365), now), '1 years ago');
    expect(formatRelativeTime(t(86400 * 730), now), '2 years ago');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```powershell
flutter test test/domain/time_formatter_test.dart
```

Expected: compile error (`time_formatter.dart` does not exist).

- [ ] **Step 3: Implement**

Create `lib/domain/time_formatter.dart`:

```dart
String formatRelativeTime(DateTime fetchedAt, DateTime now) {
  final diff = now.difference(fetchedAt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  if (diff.inDays < 30) return '${diff.inDays} days ago';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} months ago';
  return '${diff.inDays ~/ 365} years ago';
}
```

- [ ] **Step 4: Run to confirm pass**

```powershell
flutter test test/domain/time_formatter_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/domain/time_formatter.dart test/domain/time_formatter_test.dart
git commit -m "feat(domain): add formatRelativeTime pure function"
```

---

### Task 2: Browse providers (`BrowseState`, `BrowseNotifier`, `browseProvider`, `isFavoriteProvider`)

**Files:**
- Modify: `lib/ui/providers.dart`
- Create: `test/ui/browse_notifier_test.dart`

- [ ] **Step 1: Write failing notifier tests**

Create `test/ui/browse_notifier_test.dart`:

```dart
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
    final sub = container.listen(browseProvider(args), (_, __) {});
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
    final sub = container.listen(browseProvider(args), (_, __) {});
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
    final sub = container.listen(browseProvider(args), (_, __) {});
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
```

- [ ] **Step 2: Run to confirm failure**

```powershell
flutter test test/ui/browse_notifier_test.dart
```

Expected: compile error (`browseProvider`, `BrowseState` not found).

- [ ] **Step 3: Add `BrowseState`, `BrowseNotifier`, `browseProvider`, and `isFavoriteProvider` to `lib/ui/providers.dart`**

Add the following imports at the top of `providers.dart` (after existing imports):

```dart
import 'package:opds_browser/domain/models.dart';
```

Then append at the end of `lib/ui/providers.dart`:

```dart
// ── Browse screen ─────────────────────────────────────────────────────────────

class BrowseState {
  final CachedFeed feed;
  final bool isRefreshing;

  const BrowseState({required this.feed, this.isRefreshing = false});

  BrowseState copyWith({CachedFeed? feed, bool? isRefreshing}) => BrowseState(
        feed: feed ?? this.feed,
        isRefreshing: isRefreshing ?? this.isRefreshing,
      );
}

typedef BrowseArgs = (int, Uri);

class BrowseNotifier
    extends AutoDisposeFamilyAsyncNotifier<BrowseState, BrowseArgs> {
  @override
  Future<BrowseState> build(BrowseArgs arg) async {
    final (catalogId, url) = arg;
    final feed =
        await ref.read(feedRepositoryProvider).getFeed(catalogId, url);
    return BrowseState(feed: feed);
  }

  Future<void> refresh() async {
    final old = state.valueOrNull;
    if (old == null) return;
    final (catalogId, url) = arg;
    state = AsyncData(old.copyWith(isRefreshing: true));
    try {
      final feed = await ref
          .read(feedRepositoryProvider)
          .getFeed(catalogId, url, forceRefresh: true);
      state = AsyncData(BrowseState(feed: feed));
    } catch (_) {
      state = AsyncData(old.copyWith(isRefreshing: false));
      rethrow;
    }
  }
}

final browseProvider = AsyncNotifierProvider.autoDispose
    .family<BrowseNotifier, BrowseState, BrowseArgs>(BrowseNotifier.new);

final isFavoriteProvider =
    Provider.autoDispose.family<bool, BrowseArgs>((ref, args) {
  final (catalogId, url) = args;
  return ref.watch(favoritesProvider).valueOrNull?.any(
            (f) => f.catalogId == catalogId && f.url == url,
          ) ??
      false;
});
```

- [ ] **Step 4: Run to confirm pass**

```powershell
flutter test test/ui/browse_notifier_test.dart
```

Expected: all 3 tests pass.

- [ ] **Step 5: Full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/providers.dart test/ui/browse_notifier_test.dart
git commit -m "feat(ui): add BrowseState, BrowseNotifier, browseProvider, isFavoriteProvider"
```

---

### Task 3: `FavoritesNotifier.toggle()`

**Files:**
- Modify: `lib/ui/providers.dart`
- Modify: `test/ui/favorites_notifier_test.dart`

- [ ] **Step 1: Add failing tests to `test/ui/favorites_notifier_test.dart`**

Append to the `main()` function in `test/ui/favorites_notifier_test.dart`:

```dart
  test('toggle() adds favorite when not present', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(favoritesProvider.future);
    await container.read(favoritesProvider.notifier).toggle(
          1, Uri.parse('https://a.com/feed'), 'Science',
        );

    final favorites = container.read(favoritesProvider).value!;
    expect(favorites, hasLength(1));
    expect(favorites.first.title, 'Science');
    expect(favorites.first.catalogId, 1);
  });

  test('toggle() removes favorite when already present', () async {
    final seed = Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://a.com/feed'),
        title: 'Science',
        sortOrder: 0);
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(favoritesProvider.future);
    await container.read(favoritesProvider.notifier).toggle(
          1, Uri.parse('https://a.com/feed'), 'Science',
        );

    final favorites = container.read(favoritesProvider).value!;
    expect(favorites, isEmpty);
  });
```

- [ ] **Step 2: Run to confirm failure**

```powershell
flutter test test/ui/favorites_notifier_test.dart
```

Expected: FAIL — `toggle` method not found.

- [ ] **Step 3: Add `toggle()` to `FavoritesNotifier` in `lib/ui/providers.dart`**

Inside `FavoritesNotifier`, after the `remove()` method, add:

```dart
  Future<void> toggle(int catalogId, Uri url, String title) async {
    final repo = ref.read(favoritesRepositoryProvider);
    final existing = state.valueOrNull?.where(
      (f) => f.catalogId == catalogId && f.url == url,
    ).firstOrNull;
    if (existing != null) {
      await repo.remove(existing.id);
    } else {
      await repo.add(catalogId, url, title);
    }
    state = AsyncData(await repo.getAll());
  }
```

- [ ] **Step 4: Run to confirm pass**

```powershell
flutter test test/ui/favorites_notifier_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/providers.dart test/ui/favorites_notifier_test.dart
git commit -m "feat(ui): add FavoritesNotifier.toggle()"
```

---

### Task 4: BrowseScreen — test infrastructure + loading/error/content scaffold

**Files:**
- Create: `test/ui/browse_screen_test.dart`
- Modify: `lib/ui/browse_screen.dart`

- [ ] **Step 1: Write failing widget tests (infrastructure + tests 1, 3, 7, 8)**

Create `test/ui/browse_screen_test.dart`:

```dart
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
        builder: (_, __) => BrowseScreen(
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
          builder: (_, __) => BrowseScreen(catalogId: 1, url: _feedUrl),
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
}

class _ThrowingFeedRepository implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
          {bool forceRefresh = false}) async =>
      throw Exception('no connection');
}
```

- [ ] **Step 2: Run to confirm failure**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: compile error — `BrowseScreen` is a stub `StatelessWidget`, missing providers.

- [ ] **Step 3: Replace stub `lib/ui/browse_screen.dart` with full implementation**

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/time_formatter.dart';
import 'package:opds_browser/ui/providers.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  final int catalogId;
  final Uri url;

  const BrowseScreen({required this.catalogId, required this.url, super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  BrowseArgs get _args => (widget.catalogId, widget.url);

  Future<void> _refresh() async {
    try {
      await ref.read(browseProvider(_args).notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final browseAsync = ref.watch(browseProvider(_args));
    final isFavorite = ref.watch(isFavoriteProvider(_args));

    return browseAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $e'),
              TextButton(
                onPressed: () => ref.invalidate(browseProvider(_args)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (state) => _BrowseContent(
        args: _args,
        state: state,
        isFavorite: isFavorite,
        onRefresh: _refresh,
      ),
    );
  }
}

class _BrowseContent extends ConsumerWidget {
  final BrowseArgs args;
  final BrowseState state;
  final bool isFavorite;
  final Future<void> Function() onRefresh;

  const _BrowseContent({
    required this.args,
    required this.state,
    required this.isFavorite,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (catalogId, _) = args;
    final entries = state.feed.feed.entries;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.feed.feed.title),
            Text(
              formatRelativeTime(state.feed.fetchedAt, DateTime.now()),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.isRefreshing ? null : () => onRefresh(),
          ),
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            onPressed: () {
              final (catId, url) = args;
              ref.read(favoritesProvider.notifier).toggle(
                    catId, url, state.feed.feed.title,
                  );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isRefreshing) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (entries.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: Text('This folder is empty.')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = entries[index];
                          return switch (entry) {
                            NavigationEntry e => _NavigationEntryTile(
                                entry: e,
                                catalogId: catalogId,
                                key: ValueKey(e.url),
                              ),
                            BookEntry e => _BookEntryTile(
                                entry: e,
                                key: ValueKey(e.title),
                              ),
                          };
                        },
                        childCount: entries.length,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSeriesIndex(double idx) =>
    idx == idx.truncateToDouble() ? idx.toInt().toString() : idx.toString();

class _NavigationEntryTile extends StatelessWidget {
  final NavigationEntry entry;
  final int catalogId;

  const _NavigationEntryTile({
    required this.entry,
    required this.catalogId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(entry.title),
      subtitle: entry.subtitle != null
          ? Text(
              entry.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () => context.push(
        '/browse?catalogId=$catalogId&url=${Uri.encodeComponent(entry.url.toString())}',
      ),
    );
  }
}

class _BookEntryTile extends StatelessWidget {
  final BookEntry entry;

  const _BookEntryTile({required this.entry, super.key});

  @override
  Widget build(BuildContext context) {
    final authors = entry.authors.join(', ');
    final seriesText = entry.series != null
        ? (entry.seriesIndex != null
            ? '${entry.series} #${_formatSeriesIndex(entry.seriesIndex!)}'
            : entry.series!)
        : null;
    final hasSubtitle = authors.isNotEmpty || seriesText != null;

    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 80,
        child: entry.coverUrl != null
            ? CachedNetworkImage(
                imageUrl: entry.coverUrl!.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) => const Icon(Icons.book),
                errorWidget: (_, __, ___) => const Icon(Icons.book),
              )
            : const Icon(Icons.book),
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: hasSubtitle
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (authors.isNotEmpty) Text(authors),
                if (seriesText != null) Text(seriesText),
              ],
            )
          : null,
      isThreeLine: authors.isNotEmpty && seriesText != null,
    );
  }
}
```

- [ ] **Step 4: Run to confirm pass**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all 4 tests pass.

- [ ] **Step 5: Full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/browse_screen.dart test/ui/browse_screen_test.dart
git commit -m "feat(ui): add BrowseScreen scaffold with loading, error, and content states"
```

---

### Task 5: Entry list rendering tests

**Files:**
- Modify: `test/ui/browse_screen_test.dart`

- [ ] **Step 1: Add tests for navigation entry, book entry, mixed feed, and subtitle**

Append inside `main()` in `test/ui/browse_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run to confirm pass (implementation already done)**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 4: Commit**

```powershell
git add lib/ui/browse_screen.dart test/ui/browse_screen_test.dart
git commit -m "test(ui): add entry list rendering tests for BrowseScreen"
```

---

### Task 6: Refresh behavior

**Files:**
- Modify: `test/ui/browse_screen_test.dart`

- [ ] **Step 1: Add refresh tests**

Append inside `main()` in `test/ui/browse_screen_test.dart`:

```dart
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
          builder: (_, __) =>
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
```

Add the slow-fake helper class at the bottom of the test file (outside `main()`):

```dart
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
```

Add `import 'dart:async';` at the top of the test file.

- [ ] **Step 2: Run to confirm pass**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 4: Commit**

```powershell
git add test/ui/browse_screen_test.dart
git commit -m "test(ui): add BrowseScreen refresh behavior tests"
```

---

### Task 7: Favorites toggle

**Files:**
- Modify: `test/ui/browse_screen_test.dart`

- [ ] **Step 1: Add favorites toggle tests**

Append inside `main()` in `test/ui/browse_screen_test.dart`:

```dart
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
          builder: (_, __) => BrowseScreen(catalogId: 1, url: _feedUrl),
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
```

- [ ] **Step 2: Run to confirm pass**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Full quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 4: Commit**

```powershell
git add test/ui/browse_screen_test.dart
git commit -m "test(ui): add BrowseScreen favorites toggle tests"
```

---

### Task 8: Navigation tile tap

**Files:**
- Modify: `test/ui/browse_screen_test.dart`

- [ ] **Step 1: Add navigation tap test**

Append inside `main()` in `test/ui/browse_screen_test.dart`:

```dart
  testWidgets('tapping navigation entry pushes /browse with catalogId and url',
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
  });
```

- [ ] **Step 2: Run to confirm pass**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Final quality gate**

```powershell
dart run tool/check.dart
```

Expected: analyze clean, all tests pass.

- [ ] **Step 4: Final commit**

```powershell
git add test/ui/browse_screen_test.dart
git commit -m "test(ui): add navigation tile tap test for BrowseScreen"
```

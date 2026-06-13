# BrowseScreen — Design Spec

**Date:** 2026-06-13
**Step:** 7 of 11 (spec §14)
**Status:** Approved

---

## Overview

Implements the `BrowseScreen` with cache-first feed rendering, manual refresh (keeping cached content visible during fetch), and favorites toggle. Book rows are tap-inert (bottom sheet deferred to Step 9). The "Download folder" AppBar action appears but is always disabled (wired in Step 10). No domain or data files are modified.

---

## New and changed files

```
lib/domain/time_formatter.dart            # pure Dart relative-time formatter
lib/ui/providers.dart                     # add BrowseState, BrowseNotifier, browseProvider,
                                          # isFavoriteProvider; add FavoritesNotifier.toggle()
lib/ui/browse_screen.dart                 # replace stub with full implementation
test/domain/time_formatter_test.dart      # unit tests for formatRelativeTime
test/ui/browse_screen_test.dart           # widget tests for BrowseScreen
```

---

## Relative-time formatter (`lib/domain/time_formatter.dart`)

Pure function — no Flutter dependency.

```dart
String formatRelativeTime(DateTime fetchedAt, DateTime now)
```

Thresholds (using `now.difference(fetchedAt)`):

| Duration | Output |
|---|---|
| < 1 minute | `"just now"` |
| < 1 hour | `"X minutes ago"` |
| < 24 hours | `"X hours ago"` |
| < 30 days | `"X days ago"` |
| < 12 months | `"X months ago"` |
| ≥ 12 months | `"X years ago"` |

All thresholds use integer division on the raw seconds/minutes/hours/days. Unit-tested with boundary values in `test/domain/time_formatter_test.dart`.

---

## State management (`lib/ui/providers.dart`)

### `BrowseState`

```dart
class BrowseState {
  final CachedFeed feed;
  final bool isRefreshing;

  const BrowseState({required this.feed, this.isRefreshing = false});

  BrowseState copyWith({CachedFeed? feed, bool? isRefreshing}) => BrowseState(
        feed: feed ?? this.feed,
        isRefreshing: isRefreshing ?? this.isRefreshing,
      );
}
```

### `BrowseNotifier`

```dart
typedef BrowseArgs = (int catalogId, Uri url);

class BrowseNotifier
    extends AutoDisposeFamilyAsyncNotifier<BrowseState, BrowseArgs> {
  @override
  Future<BrowseState> build(BrowseArgs arg) async {
    final (catalogId, url) = arg;
    final feed = await ref.read(feedRepositoryProvider).getFeed(catalogId, url);
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
      rethrow; // widget catches and shows SnackBar
    }
  }
}

final browseProvider = AsyncNotifierProvider.autoDispose
    .family<BrowseNotifier, BrowseState, BrowseArgs>(BrowseNotifier.new);
```

### `isFavoriteProvider`

Derived from the already-loaded `favoritesProvider` — no additional DB call.

```dart
final isFavoriteProvider =
    Provider.autoDispose.family<bool, BrowseArgs>((ref, args) {
  final (catalogId, url) = args;
  return ref.watch(favoritesProvider).valueOrNull?.any(
            (f) => f.catalogId == catalogId && f.url == url,
          ) ??
      false;
});
```

### `FavoritesNotifier.toggle()` (addition to existing notifier)

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

---

## BrowseScreen widget (`lib/ui/browse_screen.dart`)

### Class structure

`BrowseScreen` is a `ConsumerStatefulWidget` (needs `State` for async refresh + mounted check on SnackBar).

```
BrowseScreen (ConsumerStatefulWidget)
  _BrowseScreenState (ConsumerState)
    _BrowseContent (ConsumerWidget)       ← rendered once feed is loaded
      _NavigationEntryTile (StatelessWidget)
      _BookEntryTile (StatelessWidget)
```

Extracting `_BrowseContent` and the tile widgets avoids rebuilding structural UI on unrelated state changes.

### Loading / error dispatch

`_BrowseScreenState.build()` watches `browseProvider(args)`:

- `AsyncLoading` → `Scaffold` with centered `CircularProgressIndicator` (only shown on first load with no cache)
- `AsyncError` → `Scaffold` with centered error message + "Retry" `TextButton` calling `ref.refresh(browseProvider(args))`
- `AsyncData(state)` → `_BrowseContent`

### `_refresh()`

```dart
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
```

### `_BrowseContent` — AppBar

```dart
AppBar(
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
      onPressed: state.isRefreshing ? null : onRefresh,
    ),
    IconButton(
      icon: Icon(isFavorite ? Icons.star : Icons.star_border),
      onPressed: () {
        final (catalogId, url) = args;
        ref.read(favoritesProvider.notifier).toggle(
              catalogId, url, state.feed.feed.title,
            );
      },
    ),
    IconButton(
      icon: const Icon(Icons.download),
      onPressed: null, // enabled in Step 10
    ),
  ],
)
```

### `_BrowseContent` — Body

```
Column
  if isRefreshing → LinearProgressIndicator (height: 2)
  Expanded
    RefreshIndicator (onRefresh: onRefresh)
      if entries.isEmpty → Center('This folder is empty.')
      else ListView.builder(entries)
        NavigationEntry → _NavigationEntryTile
        BookEntry       → _BookEntryTile
```

### `_NavigationEntryTile`

`ListTile` with:
- Leading: `const Icon(Icons.folder)`
- Title: `Text(entry.title)`
- Subtitle: entry.subtitle != null → `Text(entry.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)`
- `onTap`: `context.push('/browse?catalogId=$catalogId&url=${Uri.encodeComponent(entry.url.toString())}')`

### `_BookEntryTile`

`ListTile` with:
- Leading: `SizedBox(width: 56, height: 80, child: CachedNetworkImage(...) or placeholder Icon(Icons.book))`
- Title: `Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis)`
- Subtitle: authors line + series line (if non-null)
- `onTap`: **null** (no-op in Step 7; wired in Step 9)

Authors line: `entry.authors.join(', ')` (empty string if `authors` is empty — no "Unknown author" fallback).

Series line: `'${entry.series} #${entry.seriesIndex}'` — omit `#index` part when `seriesIndex` is null; omit entire line when `series` is null.

---

## Widget tests (`test/ui/browse_screen_test.dart`)

### Test infrastructure

```dart
// Fake repositories defined at top of test file
class FakeFeedRepository implements FeedRepository {
  final CachedFeed initialFeed;
  CachedFeed? refreshFeed; // returned on forceRefresh if non-null; throws if null
  bool forceRefreshCalled = false;

  FakeFeedRepository({required this.initialFeed, this.refreshFeed});

  @override
  Future<CachedFeed> getFeed(int catalogId, Uri url,
      {bool forceRefresh = false}) async {
    if (forceRefresh) {
      forceRefreshCalled = true;
      if (refreshFeed != null) return refreshFeed!;
      throw Exception('refresh failed');
    }
    return initialFeed;
  }
}

// FakeFavoritesRepository — same shape as start_screen_test.dart
```

Helper:

```dart
Widget buildTestApp({
  required CachedFeed feed,
  List<Favorite> favorites = const [],
  CachedFeed? refreshFeed,
  int catalogId = 1,
  Uri? url,
}) {
  final feedRepo = FakeFeedRepository(
    initialFeed: feed,
    refreshFeed: refreshFeed,
  );
  final favRepo = FakeFavoritesRepository(initialFavorites: favorites);
  return ProviderScope(
    overrides: [
      feedRepositoryProvider.overrideWithValue(feedRepo),
      favoritesRepositoryProvider.overrideWithValue(favRepo),
    ],
    child: MaterialApp(
      home: BrowseScreen(
        catalogId: catalogId,
        url: url ?? Uri.parse('http://example.com/feed'),
      ),
    ),
  );
}
```

Note: navigation tests (#14) wrap with `MaterialApp.router` + `GoRouter` with a redirect callback to capture pushed routes.

### Test cases

| # | Scenario | Verifies |
|---|---|---|
| 1 | Cache exists → renders immediately | No `CircularProgressIndicator`; feed title in AppBar |
| 2 | No cache → loading state shown | `CircularProgressIndicator` visible (use `tester.pump()` before `pumpAndSettle()`; if needed use a `Completer`-based fake to hold the future) |
| 3 | "Updated: X ago" subtitle | AppBar subtitle text matches formatter output |
| 4 | Navigation entry renders | `Icons.folder` + entry title visible |
| 5 | Book entry renders | Cover placeholder + title + authors visible |
| 6 | Mixed feed preserves order | Navigation and book rows appear in feed order |
| 7 | Empty feed shows hint | `'This folder is empty.'` visible |
| 8 | Initial load error → full-screen error + Retry | Error text and `'Retry'` button visible |
| 9 | Refresh keeps content visible | While `isRefreshing`, old content still shown; `LinearProgressIndicator` visible |
| 10 | Refresh failure → snackbar, content preserved | `SnackBar` appears; list still rendered |
| 11 | Star icon unfilled when not favorited | `Icons.star_border` present |
| 12 | Star icon filled when favorited | `Icons.star` present |
| 13 | Tap star when not favorited → adds | `FakeFavoritesRepository.favorites` grows by 1 |
| 14 | Tap navigation row → pushes browse route | Route `/browse?catalogId=...&url=...` pushed |

---

## Navigation notes

- Sub-folder navigation uses `context.push(...)` — adds to the go_router stack, preserving back navigation.
- `browseProvider` is `autoDispose` — when a screen is popped off the stack, its provider is disposed. Re-entering the screen re-runs `build()`, which hits the cache immediately (no network).
- `context.go(...)` is reserved for StartScreen and SettingsScreen (stack-replacing navigation from the AppBar).

---

## Constraints

- `flutter analyze` must be clean and `flutter test` must pass before the step is complete.
- All tests run on the host with `flutter test` — no device, no emulator.
- No existing data or domain files are modified.
- BrowseScreen book-row taps and Download-folder button are stubs; full implementations are Steps 9 and 10.

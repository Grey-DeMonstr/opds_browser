# StartScreen + Catalog CRUD + Navigation Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Flutter app with ProviderScope + go_router, implement StartScreen with catalog CRUD and favorites display, and create stub BrowseScreen/SettingsScreen for later steps.

**Architecture:** Single `lib/ui/providers.dart` holds all Riverpod infrastructure providers and `AsyncNotifier` state classes. `StartScreen` and `AddEditCatalogDialog` are separate focused widgets. Stub screens are minimal placeholders. All widget tests use `ProviderScope` overrides with in-memory fake repositories — no real DB or network in any test.

**Tech Stack:** flutter_riverpod ^3.3.2 (AsyncNotifier / Provider), go_router ^17.3.0, flutter_test (widget tests), ProviderContainer (notifier unit tests).

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `lib/main.dart` | Add ProviderScope wrapper |
| Rewrite | `lib/app.dart` | ConsumerWidget + MaterialApp.router + GoRouter |
| Create | `lib/ui/providers.dart` | All infrastructure providers + CatalogsNotifier + FavoritesNotifier |
| Create | `lib/ui/start_screen.dart` | StartScreen widget (catalog list + favorites) |
| Create | `lib/ui/browse_screen.dart` | Stub BrowseScreen (step 7 implements it) |
| Create | `lib/ui/settings_screen.dart` | Stub SettingsScreen (step 8 implements it) |
| Create | `lib/ui/widgets/add_edit_catalog_dialog.dart` | Add/Edit catalog dialog |
| Create | `test/ui/catalogs_notifier_test.dart` | Unit tests for CatalogsNotifier via ProviderContainer |
| Create | `test/ui/favorites_notifier_test.dart` | Unit tests for FavoritesNotifier via ProviderContainer |
| Create | `test/ui/start_screen_test.dart` | Widget tests for StartScreen + AddEditCatalogDialog |

---

## Task 1: Navigation shell — main.dart, app.dart, stub screens

**Files:**
- Modify: `lib/main.dart`
- Rewrite: `lib/app.dart`
- Create: `lib/ui/browse_screen.dart`
- Create: `lib/ui/settings_screen.dart`

- [ ] **Step 1.1: Update main.dart to wrap in ProviderScope**

Replace the body of `lib/main.dart` entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/app.dart';

void main() => runApp(const ProviderScope(child: OpdsBrowserApp()));
```

- [ ] **Step 1.2: Create the stub BrowseScreen**

Create `lib/ui/browse_screen.dart`:

```dart
import 'package:flutter/material.dart';

class BrowseScreen extends StatelessWidget {
  final int catalogId;
  final Uri url;

  const BrowseScreen({required this.catalogId, required this.url, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: Center(child: Text('catalogId=$catalogId\nurl=$url')),
    );
  }
}
```

- [ ] **Step 1.3: Create the stub SettingsScreen**

Create `lib/ui/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings — coming soon')),
    );
  }
}
```

- [ ] **Step 1.4: Rewrite app.dart with ConsumerWidget + MaterialApp.router**

Replace `lib/app.dart` entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/settings_screen.dart';
import 'package:opds_browser/ui/start_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const StartScreen(),
    ),
    GoRoute(
      path: '/browse',
      builder: (context, state) {
        final params = state.uri.queryParameters;
        return BrowseScreen(
          catalogId: int.parse(params['catalogId']!),
          url: Uri.parse(params['url']!),
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class OpdsBrowserApp extends ConsumerWidget {
  const OpdsBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'OPDS Browser',
      routerConfig: _router,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
    );
  }
}
```

Note: `StartScreen` doesn't exist yet — the file will not compile until Task 5. That is fine; the compiler error is resolved in Task 5. Alternatively, create a temporary placeholder `start_screen.dart` now:

```dart
// lib/ui/start_screen.dart — temporary placeholder; replaced in Task 5
import 'package:flutter/material.dart';
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}
```

- [ ] **Step 1.5: Verify the app compiles**

```powershell
flutter analyze
```

Expected: no errors (only clean output or warnings from pre-existing code).

- [ ] **Step 1.6: Commit**

```powershell
git add lib/main.dart lib/app.dart lib/ui/browse_screen.dart lib/ui/settings_screen.dart lib/ui/start_screen.dart
git commit -m "feat(ui): wire ProviderScope, go_router, and stub screens"
```

---

## Task 2: Infrastructure providers

**Files:**
- Create: `lib/ui/providers.dart`

- [ ] **Step 2.1: Create providers.dart with all infrastructure providers**

Create `lib/ui/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/caching_feed_repository.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/data/sqflite_catalog_repository.dart';
import 'package:opds_browser/data/sqflite_favorites_repository.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final opdsClientProvider = Provider<OpdsClient>(
  (ref) => Opds1Client(http.Client()),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SqfliteCatalogRepository(ref.watch(appDatabaseProvider)),
);

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => SqfliteFavoritesRepository(ref.watch(appDatabaseProvider)),
);

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => CachingFeedRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(opdsClientProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SharedPrefsSettingsRepository(),
);
```

- [ ] **Step 2.2: Verify analysis is clean**

```powershell
flutter analyze
```

Expected: no errors.

- [ ] **Step 2.3: Commit**

```powershell
git add lib/ui/providers.dart
git commit -m "feat(ui): add infrastructure providers"
```

---

## Task 3: CatalogsNotifier — tests then implementation

**Files:**
- Create: `test/ui/catalogs_notifier_test.dart`
- Modify: `lib/ui/providers.dart`

- [ ] **Step 3.1: Write failing tests for CatalogsNotifier**

Create `test/ui/catalogs_notifier_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

class FakeCatalogRepository implements CatalogRepository {
  final List<Catalog> _data;
  var _nextId = 1;

  FakeCatalogRepository({List<Catalog> initial = const []})
      : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId =
          initial.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Catalog>> getAll() async => List.unmodifiable(_data);

  @override
  Future<Catalog> add(String title, Uri rootUrl) async {
    final c = Catalog(
        id: _nextId++, title: title, rootUrl: rootUrl, protocol: 'opds1');
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

ProviderContainer makeContainer({List<Catalog> initial = const []}) {
  final container = ProviderContainer(overrides: [
    catalogRepositoryProvider.overrideWithValue(
      FakeCatalogRepository(initial: initial),
    ),
  ]);
  return container;
}

void main() {
  test('build() loads catalogs from repository', () async {
    final seed = Catalog(
        id: 1,
        title: 'A',
        rootUrl: Uri.parse('https://a.com'),
        protocol: 'opds1');
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    final catalogs = await container.read(catalogsProvider.future);
    expect(catalogs, hasLength(1));
    expect(catalogs.first.title, 'A');
  });

  test('add() inserts catalog and refreshes state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(catalogsProvider.future); // wait for build
    await container.read(catalogsProvider.notifier).add('B', Uri.parse('https://b.com'));

    final catalogs = container.read(catalogsProvider).value!;
    expect(catalogs, hasLength(1));
    expect(catalogs.first.title, 'B');
  });

  test('update() changes title and refreshes state', () async {
    final seed = Catalog(
        id: 1,
        title: 'Old',
        rootUrl: Uri.parse('https://a.com'),
        protocol: 'opds1');
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(catalogsProvider.future);
    final updated = Catalog(
        id: 1,
        title: 'New',
        rootUrl: Uri.parse('https://a.com'),
        protocol: 'opds1');
    await container.read(catalogsProvider.notifier).update(updated);

    final catalogs = container.read(catalogsProvider).value!;
    expect(catalogs.first.title, 'New');
  });

  test('delete() removes catalog and refreshes state', () async {
    final seed = Catalog(
        id: 1,
        title: 'A',
        rootUrl: Uri.parse('https://a.com'),
        protocol: 'opds1');
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(catalogsProvider.future);
    await container.read(catalogsProvider.notifier).delete(1);

    final catalogs = container.read(catalogsProvider).value!;
    expect(catalogs, isEmpty);
  });
}
```

- [ ] **Step 3.2: Run tests — expect failure (class not yet defined)**

```powershell
flutter test test/ui/catalogs_notifier_test.dart
```

Expected: compile error — `catalogsProvider` not found.

- [ ] **Step 3.3: Add CatalogsNotifier to providers.dart**

Append to the bottom of `lib/ui/providers.dart` (after existing providers):

```dart
import 'package:opds_browser/domain/entities.dart';

class CatalogsNotifier extends AsyncNotifier<List<Catalog>> {
  @override
  Future<List<Catalog>> build() async {
    return ref.watch(catalogRepositoryProvider).getAll();
  }

  Future<void> add(String title, Uri rootUrl) async {
    final repo = ref.read(catalogRepositoryProvider);
    await repo.add(title, rootUrl);
    state = AsyncData(await repo.getAll());
  }

  Future<void> update(Catalog catalog) async {
    final repo = ref.read(catalogRepositoryProvider);
    await repo.update(catalog);
    state = AsyncData(await repo.getAll());
  }

  Future<void> delete(int catalogId) async {
    final repo = ref.read(catalogRepositoryProvider);
    await repo.delete(catalogId);
    state = AsyncData(await repo.getAll());
  }
}

final catalogsProvider =
    AsyncNotifierProvider<CatalogsNotifier, List<Catalog>>(
        CatalogsNotifier.new);
```

Note: add the `entities.dart` import to the top import block. The file already imports `repositories.dart`; add alongside it:

```dart
import 'package:opds_browser/domain/entities.dart';
```

- [ ] **Step 3.4: Run tests — expect all pass**

```powershell
flutter test test/ui/catalogs_notifier_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 3.5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/catalogs_notifier_test.dart
git commit -m "feat(ui): add CatalogsNotifier with CRUD, tests passing"
```

---

## Task 4: FavoritesNotifier — tests then implementation

**Files:**
- Create: `test/ui/favorites_notifier_test.dart`
- Modify: `lib/ui/providers.dart`

- [ ] **Step 4.1: Write failing tests for FavoritesNotifier**

Create `test/ui/favorites_notifier_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

class FakeFavoritesRepository implements FavoritesRepository {
  final List<Favorite> _data;
  var _nextId = 1;

  FakeFavoritesRepository({List<Favorite> initial = const []})
      : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId =
          initial.map((f) => f.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

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

ProviderContainer makeContainer({List<Favorite> initial = const []}) {
  return ProviderContainer(overrides: [
    favoritesRepositoryProvider.overrideWithValue(
      FakeFavoritesRepository(initial: initial),
    ),
  ]);
}

void main() {
  test('build() loads favorites from repository', () async {
    final seed = Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://a.com/feed'),
        title: 'Science',
        sortOrder: 0);
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    final favorites = await container.read(favoritesProvider.future);
    expect(favorites, hasLength(1));
    expect(favorites.first.title, 'Science');
  });

  test('remove() deletes favorite and refreshes state', () async {
    final seed = Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://a.com/feed'),
        title: 'Science',
        sortOrder: 0);
    final container = makeContainer(initial: [seed]);
    addTearDown(container.dispose);

    await container.read(favoritesProvider.future);
    await container.read(favoritesProvider.notifier).remove(1);

    final favorites = container.read(favoritesProvider).value!;
    expect(favorites, isEmpty);
  });
}
```

- [ ] **Step 4.2: Run tests — expect failure**

```powershell
flutter test test/ui/favorites_notifier_test.dart
```

Expected: compile error — `favoritesProvider` not found.

- [ ] **Step 4.3: Add FavoritesNotifier to providers.dart**

Append to the bottom of `lib/ui/providers.dart`:

```dart
class FavoritesNotifier extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() async {
    return ref.watch(favoritesRepositoryProvider).getAll();
  }

  Future<void> remove(int favoriteId) async {
    final repo = ref.read(favoritesRepositoryProvider);
    await repo.remove(favoriteId);
    state = AsyncData(await repo.getAll());
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(
        FavoritesNotifier.new);
```

- [ ] **Step 4.4: Run tests — expect all pass**

```powershell
flutter test test/ui/favorites_notifier_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 4.5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/favorites_notifier_test.dart
git commit -m "feat(ui): add FavoritesNotifier with remove, tests passing"
```

---

## Task 5: StartScreen scaffold + empty state

**Files:**
- Rewrite: `lib/ui/start_screen.dart`
- Create: `test/ui/start_screen_test.dart`

- [ ] **Step 5.1: Write failing widget test for empty state**

Create `test/ui/start_screen_test.dart` with the shared test infrastructure and the first test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/start_screen.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class FakeCatalogRepository implements CatalogRepository {
  final List<Catalog> _data;
  var _nextId = 1;

  FakeCatalogRepository({List<Catalog> initial = const []})
      : _data = List.of(initial) {
    if (initial.isNotEmpty) {
      _nextId =
          initial.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<List<Catalog>> getAll() async => List.unmodifiable(_data);

  @override
  Future<Catalog> add(String title, Uri rootUrl) async {
    final c = Catalog(
        id: _nextId++, title: title, rootUrl: rootUrl, protocol: 'opds1');
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
      _nextId =
          initial.map((f) => f.id).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

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

class FakeOpdsClient implements OpdsClient {
  final bool probeResult;
  FakeOpdsClient({this.probeResult = true});

  @override
  Future<ParsedFeed> fetchFeed(Uri url) => throw UnimplementedError();

  @override
  Future<bool> probe(Uri url) async => probeResult;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

GoRouter _makeRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const StartScreen()),
      GoRoute(path: '/browse', builder: (_, __) => const SizedBox()),
      GoRoute(path: '/settings', builder: (_, __) => const SizedBox()),
    ],
  );
}

Widget buildApp({
  List<Catalog> catalogs = const [],
  List<Favorite> favorites = const [],
  bool probeResult = true,
  GoRouter? router,
}) {
  return ProviderScope(
    overrides: [
      catalogRepositoryProvider
          .overrideWithValue(FakeCatalogRepository(initial: catalogs)),
      favoritesRepositoryProvider
          .overrideWithValue(FakeFavoritesRepository(initial: favorites)),
      opdsClientProvider
          .overrideWithValue(FakeOpdsClient(probeResult: probeResult)),
    ],
    child: MaterialApp.router(routerConfig: router ?? _makeRouter()),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('empty state: shows hint text and FAB', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('No catalogues yet. Tap + to add one.'), findsOneWidget);
    expect(find.text('Add catalogue'), findsOneWidget); // FAB label
  });
}
```

- [ ] **Step 5.2: Run test — expect failure**

```powershell
flutter test test/ui/start_screen_test.dart --name "empty state"
```

Expected: compile error or failure because `StartScreen` is a placeholder.

- [ ] **Step 5.3: Implement StartScreen with empty state**

Replace `lib/ui/start_screen.dart` entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/widgets/add_edit_catalog_dialog.dart';

class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogsAsync = ref.watch(catalogsProvider);
    final favoritesAsync = ref.watch(favoritesProvider);

    return catalogsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (catalogs) => favoritesAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Error: $e')),
        ),
        data: (favorites) => _StartScreenContent(
          catalogs: catalogs,
          favorites: favorites,
        ),
      ),
    );
  }
}

class _StartScreenContent extends ConsumerWidget {
  final List<Catalog> catalogs;
  final List<Favorite> favorites;

  const _StartScreenContent({
    required this.catalogs,
    required this.favorites,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPDS Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const AddEditCatalogDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add catalogue'),
      ),
      body: CustomScrollView(
        slivers: [
          if (catalogs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No catalogues yet. Tap + to add one.'),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _CatalogTile(catalog: catalogs[index]),
                childCount: catalogs.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogTile extends ConsumerWidget {
  final Catalog catalog;
  const _CatalogTile({required this.catalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(catalog.title),
      subtitle: Text(
        catalog.rootUrl.toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.push(
        '/browse?catalogId=${catalog.id}&url=${Uri.encodeComponent(catalog.rootUrl.toString())}',
      ),
      trailing: PopupMenuButton<_CatalogMenuAction>(
        onSelected: (action) => _onMenuAction(context, ref, action),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _CatalogMenuAction.edit,
            child: Text('Edit'),
          ),
          PopupMenuItem(
            value: _CatalogMenuAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onMenuAction(
      BuildContext context, WidgetRef ref, _CatalogMenuAction action) {
    switch (action) {
      case _CatalogMenuAction.edit:
        showDialog<void>(
          context: context,
          builder: (_) => AddEditCatalogDialog(catalog: catalog),
        );
      case _CatalogMenuAction.delete:
        showDialog<void>(
          context: context,
          builder: (_) => _DeleteCatalogDialog(catalog: catalog),
        );
    }
  }
}

enum _CatalogMenuAction { edit, delete }

class _DeleteCatalogDialog extends ConsumerWidget {
  final Catalog catalog;
  const _DeleteCatalogDialog({required this.catalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Delete catalogue?'),
      content: const Text(
        'This will also remove its favourites and cached feeds.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            await ref.read(catalogsProvider.notifier).delete(catalog.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
```

Note: `AddEditCatalogDialog` doesn't exist yet. Create a temporary stub in `lib/ui/widgets/add_edit_catalog_dialog.dart`:

```dart
// lib/ui/widgets/add_edit_catalog_dialog.dart — stub; replaced in Task 8
import 'package:flutter/material.dart';
import 'package:opds_browser/domain/entities.dart';

class AddEditCatalogDialog extends StatelessWidget {
  final Catalog? catalog;
  const AddEditCatalogDialog({this.catalog, super.key});

  @override
  Widget build(BuildContext context) => const AlertDialog(
        title: Text('stub'),
      );
}
```

- [ ] **Step 5.4: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "empty state"
```

Expected: 1 test passes.

- [ ] **Step 5.5: Commit**

```powershell
git add lib/ui/start_screen.dart lib/ui/widgets/add_edit_catalog_dialog.dart test/ui/start_screen_test.dart
git commit -m "feat(ui): add StartScreen scaffold and empty state"
```

---

## Task 6: StartScreen — catalog list rendering

**Files:**
- Modify: `test/ui/start_screen_test.dart` (add test)
- No implementation change needed (catalog list is already in Task 5)

- [ ] **Step 6.1: Add catalog list rendering test**

Append inside the `main()` block of `test/ui/start_screen_test.dart`:

```dart
  testWidgets('catalog list: renders two catalogs with titles', (tester) async {
    final catalogs = [
      Catalog(
          id: 1,
          title: 'Project Gutenberg',
          rootUrl: Uri.parse('https://gutenberg.org/opds'),
          protocol: 'opds1'),
      Catalog(
          id: 2,
          title: 'Standard Ebooks',
          rootUrl: Uri.parse('https://standardebooks.org/opds'),
          protocol: 'opds1'),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs));
    await tester.pumpAndSettle();

    expect(find.text('Project Gutenberg'), findsOneWidget);
    expect(find.text('Standard Ebooks'), findsOneWidget);
    // Hint text must NOT appear when list is non-empty
    expect(
        find.text('No catalogues yet. Tap + to add one.'), findsNothing);
  });
```

- [ ] **Step 6.2: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "catalog list"
```

Expected: 1 test passes (implementation is already in place from Task 5).

- [ ] **Step 6.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add catalog list rendering test"
```

---

## Task 7: StartScreen — favorites section

**Files:**
- Modify: `lib/ui/start_screen.dart` (add favorites sliver)
- Modify: `test/ui/start_screen_test.dart` (add tests)

- [ ] **Step 7.1: Write failing tests for favorites section**

Append inside `main()` in `test/ui/start_screen_test.dart`:

```dart
  testWidgets('favorites section: hidden when list is empty', (tester) async {
    final catalogs = [
      Catalog(
          id: 1,
          title: 'Gutenberg',
          rootUrl: Uri.parse('https://gutenberg.org/opds'),
          protocol: 'opds1'),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs, favorites: []));
    await tester.pumpAndSettle();

    expect(find.text('Favourites'), findsNothing);
  });

  testWidgets('favorites section: shows when non-empty', (tester) async {
    final catalogs = [
      Catalog(
          id: 1,
          title: 'Gutenberg',
          rootUrl: Uri.parse('https://gutenberg.org/opds'),
          protocol: 'opds1'),
    ];
    final favorites = [
      Favorite(
          id: 1,
          catalogId: 1,
          url: Uri.parse('https://gutenberg.org/opds/science'),
          title: 'Science',
          sortOrder: 0),
    ];
    await tester.pumpWidget(buildApp(catalogs: catalogs, favorites: favorites));
    await tester.pumpAndSettle();

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Science'), findsOneWidget);
  });
```

- [ ] **Step 7.2: Run tests — expect failure**

```powershell
flutter test test/ui/start_screen_test.dart --name "favorites section"
```

Expected: tests fail because the favorites section is not yet rendered.

- [ ] **Step 7.3: Add favorites section to _StartScreenContent**

In `lib/ui/start_screen.dart`, update the `_StartScreenContent.build()` method. Replace the `body: CustomScrollView(...)` body with:

```dart
      body: CustomScrollView(
        slivers: [
          if (favorites.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Favourites',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _FavoriteTile(favorite: favorites[index], catalogs: catalogs),
                childCount: favorites.length,
              ),
            ),
          ],
          if (catalogs.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Catalogues',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (catalogs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No catalogues yet. Tap + to add one.'),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _CatalogTile(catalog: catalogs[index]),
                childCount: catalogs.length,
              ),
            ),
        ],
      ),
```

Then add `_FavoriteTile` class below `_DeleteCatalogDialog` in the same file:

```dart
class _FavoriteTile extends ConsumerWidget {
  final Favorite favorite;
  final List<Catalog> catalogs;

  const _FavoriteTile({required this.favorite, required this.catalogs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentTitle = catalogs
        .where((c) => c.id == favorite.catalogId)
        .map((c) => c.title)
        .firstOrNull ?? '';

    return ListTile(
      title: Text(favorite.title),
      subtitle: Text(parentTitle),
      onTap: () => context.push(
        '/browse?catalogId=${favorite.catalogId}&url=${Uri.encodeComponent(favorite.url.toString())}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (_) async {
          await ref.read(favoritesProvider.notifier).remove(favorite.id);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'remove',
            child: Text('Remove from favourites'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7.4: Run tests — expect all pass**

```powershell
flutter test test/ui/start_screen_test.dart
```

Expected: all 4 tests pass (empty state, catalog list, favorites hidden, favorites shown).

- [ ] **Step 7.5: Commit**

```powershell
git add lib/ui/start_screen.dart test/ui/start_screen_test.dart
git commit -m "feat(ui): add favorites section to StartScreen"
```

---

## Task 8: AddEditCatalogDialog — layout and fields

**Files:**
- Rewrite: `lib/ui/widgets/add_edit_catalog_dialog.dart`
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 8.1: Write failing test — FAB opens dialog with fields**

Append inside `main()` in `test/ui/start_screen_test.dart`:

```dart
  testWidgets('FAB opens Add dialog with Title and URL fields', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Add catalogue'), findsWidgets); // dialog title
    expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'URL'), findsOneWidget);
  });
```

- [ ] **Step 8.2: Run test — expect failure**

```powershell
flutter test test/ui/start_screen_test.dart --name "FAB opens"
```

Expected: fails — dialog shows the stub ("stub" title), not "Add catalogue" with fields.

- [ ] **Step 8.3: Implement dialog layout (no save logic yet)**

Replace `lib/ui/widgets/add_edit_catalog_dialog.dart` entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/ui/providers.dart';

class AddEditCatalogDialog extends ConsumerStatefulWidget {
  final Catalog? catalog;

  const AddEditCatalogDialog({this.catalog, super.key});

  @override
  ConsumerState<AddEditCatalogDialog> createState() =>
      _AddEditCatalogDialogState();
}

class _AddEditCatalogDialogState extends ConsumerState<AddEditCatalogDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  bool _probing = false;
  String? _probeError;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.catalog?.title ?? '');
    _urlCtrl = TextEditingController(
        text: widget.catalog?.rootUrl.toString() ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Uri _parseUrl(String raw) {
    final trimmed = raw.trim();
    return trimmed.contains('://') ? Uri.parse(trimmed) : Uri.parse('https://$trimmed');
  }

  Future<void> _submit({bool skipProbe = false}) async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleCtrl.text.trim();
    final url = _parseUrl(_urlCtrl.text);

    if (!skipProbe) {
      setState(() {
        _probing = true;
        _probeError = null;
      });
      bool ok;
      try {
        ok = await ref.read(opdsClientProvider).probe(url);
      } on OpdsException catch (e) {
        if (mounted) setState(() { _probing = false; _probeError = e.message; });
        return;
      }
      if (mounted) setState(() { _probing = false; });
      if (!ok) {
        if (mounted) setState(() { _probeError = 'Not a supported OPDS catalogue'; });
        return;
      }
    }

    if (widget.catalog == null) {
      await ref.read(catalogsProvider.notifier).add(title, url);
    } else {
      await ref.read(catalogsProvider.notifier).update(
            Catalog(
              id: widget.catalog!.id,
              title: title,
              rootUrl: url,
              protocol: widget.catalog!.protocol,
            ),
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.catalog != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit catalogue' : 'Add catalogue'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'URL'),
              keyboardType: TextInputType.url,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'URL is required' : null,
            ),
            if (_probeError != null) ...[
              const SizedBox(height: 8),
              Text(
                _probeError!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13),
              ),
              TextButton(
                onPressed: _probing ? null : () => _submit(skipProbe: true),
                child: const Text('Save anyway'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _probing ? null : _submit,
          child: _probing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 8.4: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "FAB opens"
```

Expected: 1 test passes.

- [ ] **Step 8.5: Commit**

```powershell
git add lib/ui/widgets/add_edit_catalog_dialog.dart test/ui/start_screen_test.dart
git commit -m "feat(ui): implement AddEditCatalogDialog layout"
```

---

## Task 9: Dialog — title validation

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 9.1: Write failing test for empty title validation**

Append inside `main()`:

```dart
  testWidgets('dialog: shows validation error for empty title', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    // Leave title empty, fill in URL
    await tester.enterText(find.widgetWithText(TextFormField, 'URL'), 'example.com');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
  });
```

- [ ] **Step 9.2: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "validation error"
```

Expected: passes (validation is already implemented in Task 8).

- [ ] **Step 9.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add dialog title validation test"
```

---

## Task 10: Dialog — add catalog success (probe passes)

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 10.1: Write failing test**

Append inside `main()`:

```dart
  testWidgets('dialog: add catalog when probe passes — catalog appears in list',
      (tester) async {
    await tester.pumpWidget(buildApp(probeResult: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'My Library');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://library.example.com/opds');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.byType(AlertDialog), findsNothing);
    // Catalog should appear in the list
    expect(find.text('My Library'), findsOneWidget);
  });
```

- [ ] **Step 10.2: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "add catalog when probe passes"
```

Expected: passes (the full save flow is already implemented in Task 8).

- [ ] **Step 10.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add catalog success flow test"
```

---

## Task 11: Dialog — probe failure and "Save anyway"

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 11.1: Write failing tests**

Append inside `main()`:

```dart
  testWidgets('dialog: probe failure shows error and Save anyway button',
      (tester) async {
    await tester.pumpWidget(buildApp(probeResult: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add catalogue'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'), 'Bad Feed');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://notopds.example.com');
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
        find.widgetWithText(TextFormField, 'Title'), 'Force Save');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://notopds.example.com');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Save anyway'));
    await tester.pumpAndSettle();

    // Dialog must be dismissed and catalog saved
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Force Save'), findsOneWidget);
  });
```

- [ ] **Step 11.2: Run tests — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "probe failure"
```

Expected: both tests pass (probe failure handling is already implemented in Task 8).

- [ ] **Step 11.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add probe failure and Save anyway tests"
```

---

## Task 12: Dialog — edit mode pre-fills fields

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 12.1: Write failing test**

Append inside `main()`:

```dart
  testWidgets('dialog: edit mode pre-fills title and URL', (tester) async {
    final catalog = Catalog(
        id: 1,
        title: 'Project Gutenberg',
        rootUrl: Uri.parse('https://gutenberg.org/opds'),
        protocol: 'opds1');
    await tester.pumpWidget(buildApp(catalogs: [catalog]));
    await tester.pumpAndSettle();

    // Tap the popup menu trailing button on the catalog tile
    await tester.tap(find.byType(PopupMenuButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // Pre-filled title
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Project Gutenberg',
    );
  });
```

- [ ] **Step 12.2: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "edit mode"
```

Expected: passes (pre-fill is implemented in Task 8 via `initState`).

- [ ] **Step 12.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add edit mode pre-fill test"
```

---

## Task 13: StartScreen — delete catalog

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 13.1: Write failing tests for delete flow**

Append inside `main()`:

```dart
  testWidgets('delete: tapping Delete shows confirmation dialog', (tester) async {
    final catalog = Catalog(
        id: 1,
        title: 'My Catalog',
        rootUrl: Uri.parse('https://example.com/opds'),
        protocol: 'opds1');
    await tester.pumpWidget(buildApp(catalogs: [catalog]));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton).first);
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
        protocol: 'opds1');
    await tester.pumpWidget(buildApp(catalogs: [catalog]));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton).first);
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
```

- [ ] **Step 13.2: Run tests — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "delete"
```

Expected: both tests pass (delete flow is implemented in Task 5).

- [ ] **Step 13.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add delete catalog confirmation and confirm tests"
```

---

## Task 14: StartScreen — catalog row navigation

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 14.1: Write failing navigation test**

Append inside `main()`:

```dart
  testWidgets('catalog row tap navigates to /browse with correct params',
      (tester) async {
    final catalog = Catalog(
        id: 42,
        title: 'My Library',
        rootUrl: Uri.parse('https://library.example.com/opds'),
        protocol: 'opds1');

    String? capturedUri;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const StartScreen()),
        GoRoute(
          path: '/browse',
          builder: (_, state) {
            capturedUri = state.uri.toString();
            return const SizedBox();
          },
        ),
        GoRoute(path: '/settings', builder: (_, __) => const SizedBox()),
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
```

- [ ] **Step 14.2: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "navigates to"
```

Expected: passes (navigation is implemented in Task 5).

- [ ] **Step 14.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add catalog row navigation test"
```

---

## Task 15: StartScreen — remove favourite

**Files:**
- Modify: `test/ui/start_screen_test.dart`

- [ ] **Step 15.1: Write failing test for remove favourite**

Append inside `main()`:

```dart
  testWidgets('remove favourite: item disappears after Remove tapped',
      (tester) async {
    final catalog = Catalog(
        id: 1,
        title: 'Gutenberg',
        rootUrl: Uri.parse('https://gutenberg.org/opds'),
        protocol: 'opds1');
    final favorite = Favorite(
        id: 1,
        catalogId: 1,
        url: Uri.parse('https://gutenberg.org/opds/science'),
        title: 'Science',
        sortOrder: 0);

    await tester.pumpWidget(
        buildApp(catalogs: [catalog], favorites: [favorite]));
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsOneWidget);

    // Tap the PopupMenuButton on the favorite tile (first one is the favorite's)
    await tester.tap(find.byType(PopupMenuButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove from favourites'));
    await tester.pumpAndSettle();

    expect(find.text('Science'), findsNothing);
  });
```

- [ ] **Step 15.2: Run test — expect pass**

```powershell
flutter test test/ui/start_screen_test.dart --name "remove favourite"
```

Expected: passes (remove favourite is implemented in Task 7).

- [ ] **Step 15.3: Commit**

```powershell
git add test/ui/start_screen_test.dart
git commit -m "test(ui): add remove favourite test"
```

---

## Task 16: Final quality gate

**Files:** none (run-only step)

- [ ] **Step 16.1: Run full test suite**

```powershell
flutter test
```

Expected: all tests pass (catalogs notifier, favorites notifier, start screen suite).

- [ ] **Step 16.2: Run static analysis**

```powershell
flutter analyze
```

Expected: no issues found.

- [ ] **Step 16.3: Commit if any fixes were needed**

If analyze or tests found issues that required code changes, commit:

```powershell
git add -A
git commit -m "fix(ui): resolve analyze issues from step 6"
```

If everything was already clean, no commit needed.

---

## Spec coverage check

| Spec requirement | Task |
|---|---|
| ProviderScope wrapping app | Task 1 |
| go_router with `/`, `/browse`, `/settings` routes | Task 1 |
| BrowseScreen stub | Task 1 |
| SettingsScreen stub | Task 1 |
| Infrastructure Provider<T> per dependency | Task 2 |
| Opds1Client(http.Client()) wiring | Task 2 |
| CatalogsNotifier (add/update/delete) | Task 3 |
| FavoritesNotifier (remove) | Task 4 |
| StartScreen empty state | Task 5 |
| AppBar "OPDS Browser" + Settings icon | Task 5 |
| FAB "Add catalogue" | Task 5 |
| Catalog list (title + URL) | Task 5/6 |
| Catalog trailing Edit/Delete menu | Task 5 |
| Catalog tap → /browse | Task 5/14 |
| Delete confirmation dialog | Task 5/13 |
| Favorites section hidden when empty | Task 7 |
| Favorites section shown with title + parent catalog | Task 7 |
| Favourite tap → /browse | Task 7 |
| Remove from favourites | Task 7/15 |
| AddEditCatalogDialog layout (Title + URL fields) | Task 8 |
| Add mode title "Add catalogue" | Task 8 |
| Edit mode pre-fills fields + title "Edit catalogue" | Task 8/12 |
| Title validation (non-empty) | Task 8/9 |
| Auto-prepend https:// | Task 8 |
| Probe call on Save | Task 8/10 |
| Loading indicator during probe | Task 8 |
| Probe failure → error text + Save anyway | Task 8/11 |
| Save anyway skips probe | Task 8/11 |
| OpdsException catch (network/HTTP errors) | Task 8 |

# StartScreen + Catalog CRUD + Navigation Shell — Design Spec

**Date:** 2026-06-13
**Step:** 6 of 11 (spec §14)
**Status:** Approved

---

## Overview

Wires the Flutter app with `ProviderScope`, `go_router`, and Riverpod providers, then implements the `StartScreen` with catalog CRUD and favorites display. `BrowseScreen` and `SettingsScreen` are minimal stubs; full implementations follow in steps 7 and 8.

---

## New and changed files

```
lib/main.dart                              # add ProviderScope
lib/app.dart                               # rewrite: ConsumerWidget + MaterialApp.router + GoRouter
lib/ui/providers.dart                      # all infrastructure providers + CatalogsNotifier + FavoritesNotifier
lib/ui/start_screen.dart                   # StartScreen widget
lib/ui/browse_screen.dart                  # stub BrowseScreen
lib/ui/settings_screen.dart               # stub SettingsScreen
lib/ui/widgets/add_edit_catalog_dialog.dart# Add/Edit dialog
test/ui/start_screen_test.dart             # widget tests
```

No existing data/domain files are modified.

---

## Navigation shell

### `main.dart`

Wrap `runApp` with `ProviderScope`:

```dart
void main() => runApp(const ProviderScope(child: OpdsBrowserApp()));
```

### `app.dart`

Replace the current placeholder with a `ConsumerWidget` using `MaterialApp.router`. The router is a file-level `GoRouter` constant (no provider dependency in step 6):

```
Routes:
  /              → StartScreen
  /browse        → BrowseScreen(catalogId: int, url: Uri)   [query params]
  /settings      → SettingsScreen
```

BrowseScreen receives `catalogId` (int) and `url` (Uri) as go_router query parameters parsed from `state.uri.queryParameters`. SettingsScreen has no parameters.

Theme: Material 3, `colorSchemeSeed: Colors.indigo`, light + dark themes as in the current placeholder.

---

## Providers (`lib/ui/providers.dart`)

### Infrastructure providers

One `Provider<T>` per dependency, no lazy initialization complexity:

| Provider | Type | Implementation |
|---|---|---|
| `appDatabaseProvider` | `Provider<AppDatabase>` | `AppDatabase()` |
| `catalogRepositoryProvider` | `Provider<CatalogRepository>` | `SqfliteCatalogRepository(db)` |
| `favoritesRepositoryProvider` | `Provider<FavoritesRepository>` | `SqfliteFavoritesRepository(db)` |
| `feedRepositoryProvider` | `Provider<FeedRepository>` | `CachingFeedRepository(db, client)` |
| `settingsRepositoryProvider` | `Provider<SettingsRepository>` | `SharedPrefsSettingsRepository()` |
| `opdsClientProvider` | `Provider<OpdsClient>` | `Opds1Client()` |

All use `ref.watch` to compose their dependencies.

### State providers

**`CatalogsNotifier extends AsyncNotifier<List<Catalog>>`**

- `build()` → `ref.read(catalogRepositoryProvider).getAll()`
- `add(String title, Uri rootUrl)` → `repo.add(title, rootUrl)` then refresh state
- `update(Catalog catalog)` → `repo.update(catalog)` then refresh state
- `delete(int catalogId)` → `repo.delete(catalogId)` then refresh state

State refresh is done by re-calling `getAll()` and assigning to `state`.

```dart
final catalogsProvider =
    AsyncNotifierProvider<CatalogsNotifier, List<Catalog>>(CatalogsNotifier.new);
```

**`FavoritesNotifier extends AsyncNotifier<List<Favorite>>`**

- `build()` → `ref.read(favoritesRepositoryProvider).getAll()`
- `remove(int favoriteId)` → `repo.remove(favoriteId)` then refresh state

```dart
final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(FavoritesNotifier.new);
```

---

## StartScreen (`lib/ui/start_screen.dart`)

`ConsumerWidget`. Reads `catalogsProvider` and `favoritesProvider`.

### Loading / error states

Both providers return `AsyncValue<...>`. While either is loading, show a centered `CircularProgressIndicator`. On error, show centered error text with the exception message.

### Layout: `CustomScrollView` with slivers

**Favorites section** (hidden when list is empty):

- `SliverToBoxAdapter` header: "Favourites" text in `ListTile`-style padding
- `SliverList` of rows:
  - Primary text: favorite title
  - Secondary text: parent catalog title (looked up from the catalogs list)
  - Trailing: `PopupMenuButton` with item "Remove from favourites" → calls `ref.read(favoritesProvider.notifier).remove(favorite.id)`
  - Tap: `context.go('/browse?catalogId=${fav.catalogId}&url=${Uri.encodeComponent(fav.url.toString())}')`

**Catalogs section** (always shown):

- `SliverToBoxAdapter` header: "Catalogues" text
- When list is empty → `SliverFillRemaining` with centered hint: "No catalogues yet. Tap + to add one."
- `SliverList` of rows:
  - Primary text: catalog title
  - Secondary text: catalog root URL (1 line, ellipsized)
  - Trailing: `PopupMenuButton` with items "Edit" and "Delete"
  - Tap: `context.go('/browse?catalogId=${cat.id}&url=${Uri.encodeComponent(cat.rootUrl.toString())}')`

**AppBar:**
- Title: "OPDS Browser"
- Actions: Settings icon → `context.go('/settings')`

**FAB:** `FloatingActionButton.extended`, icon `+`, label "Add catalogue" → `showDialog(AddEditCatalogDialog(catalog: null))`

### Delete confirmation

`showDialog` with an `AlertDialog`:
- Title: "Delete catalogue?"
- Content: "This will also remove its favourites and cached feeds."
- Actions: Cancel / Delete (destructive color)
- On Delete: `ref.read(catalogsProvider.notifier).delete(catalog.id)`

---

## AddEditCatalogDialog (`lib/ui/widgets/add_edit_catalog_dialog.dart`)

`ConsumerStatefulWidget`. Constructor: `const AddEditCatalogDialog({this.catalog})` where `Catalog? catalog` — null means Add mode, non-null means Edit.

### Fields

- **Title** — `TextFormField`, validator: non-empty after trim, label "Title"
- **URL** — `TextFormField`, validator: non-empty after trim, label "URL", `keyboardType: TextInputType.url`

In Edit mode, pre-fill both fields from `catalog.title` and `catalog.rootUrl.toString()`.

### Internal state

```dart
bool _probing = false;
String? _probeError;       // non-null when probe has failed
```

### Save flow

```
_submit({bool skipProbe = false}):
  1. Validate form (Form.validate()); return if invalid.
  2. title = title field text, trimmed
  3. rawUrl = URL field text, trimmed
  4. url = rawUrl.contains('://') ? Uri.parse(rawUrl) : Uri.parse('https://$rawUrl')
  5. if not skipProbe:
       setState(_probing = true, _probeError = null)
       ok = await ref.read(opdsClientProvider).probe(url)
       setState(_probing = false)
       if not ok:
         setState(_probeError = 'Not a supported OPDS catalogue')
         return
  6. if catalog == null: await ref.read(catalogsProvider.notifier).add(title, url)
     else:               await ref.read(catalogsProvider.notifier).update(
                           Catalog(id: catalog.id, title: title, rootUrl: url, protocol: catalog.protocol))
  7. if mounted: Navigator.of(context).pop()
```

### Dialog layout

- `AlertDialog` with:
  - Title: "Add catalogue" / "Edit catalogue"
  - Content: `Form` wrapping the two `TextFormField`s stacked vertically; below URL field: if `_probeError != null`, show red error text + a "Save anyway" `TextButton` that calls `_submit(skipProbe: true)`
  - Actions: Cancel / Save (Save shows `SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))` when `_probing == true`, disabled during probing)

---

## Stub screens

### `lib/ui/browse_screen.dart`

```dart
class BrowseScreen extends StatelessWidget {
  final int catalogId;
  final Uri url;
  const BrowseScreen({required this.catalogId, required this.url, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Browse')),
    body: Center(child: Text('catalogId=$catalogId\nurl=$url')),
  );
}
```

### `lib/ui/settings_screen.dart`

```dart
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: const Center(child: Text('Settings — coming soon')),
  );
}
```

---

## Widget tests (`test/ui/start_screen_test.dart`)

### Test infrastructure

Fake implementations (defined at the top of the test file, not in separate files):

- `FakeCatalogRepository implements CatalogRepository` — holds an in-memory `List<Catalog>`, supports all CRUD methods, assigns auto-incrementing ids.
- `FakeFavoritesRepository implements FavoritesRepository` — holds an in-memory `List<Favorite>`, supports `getAll`, `remove`, `isFavorite`, `add`.
- `FakeOpdsClient implements OpdsClient` — constructor takes `bool probeResult`; `probe()` returns it; `fetchFeed()` is not called in these tests.

Helper:

```dart
Widget buildTestApp({
  List<Catalog> catalogs = const [],
  List<Favorite> favorites = const [],
  bool probeResult = true,
}) {
  final catalogRepo = FakeCatalogRepository(initialCatalogs: catalogs);
  final favoritesRepo = FakeFavoritesRepository(initialFavorites: favorites);
  return ProviderScope(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
      favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
      opdsClientProvider.overrideWithValue(FakeOpdsClient(probeResult: probeResult)),
    ],
    child: MaterialApp(home: const StartScreen()),
  );
}
```

Note: most tests use the plain `MaterialApp(home: const StartScreen())` helper above. For test #13 (navigation assertion), wrap with a `MaterialApp.router` using a `GoRouter` that captures the navigation target in a local variable — do not use a real device router. A minimal approach: use `GoRouter`'s `navigatorKey` or a redirect callback to record the pushed route.

### Test cases

| # | Scenario | Verifies |
|---|---|---|
| 1 | Empty state | No catalogs → hint text visible, FAB visible |
| 2 | Catalog list renders | 2 catalogs → both titles visible |
| 3 | Favorites section hidden | Empty favorites list → no favorites section |
| 4 | Favorites section shown | 2 favorites → section visible, titles visible |
| 5 | FAB opens dialog | Tap FAB → dialog with Title and URL fields appears |
| 6 | Dialog validates empty title | Tap Save with empty title → inline validation error |
| 7 | Add success (probe passes) | Fill fields, probeResult=true → catalog added, dialog closes |
| 8 | Add — probe fails | probeResult=false → error text shown, "Save anyway" button appears |
| 9 | "Save anyway" bypasses probe | Tap "Save anyway" → catalog added (probe=false, still saved) |
| 10 | Edit pre-fills fields | Tap Edit → dialog opens with existing title and URL |
| 11 | Delete shows confirmation | Tap Delete → confirmation AlertDialog appears |
| 12 | Delete confirmed | Confirm deletion → catalog removed from list |
| 13 | Tap catalog row navigates | Tap catalog row → navigates to `/browse?catalogId=...&url=...` |
| 14 | Remove favourite | Tap "Remove from favourites" → entry removed from list |

---

## Constraints

- `flutter analyze` must be clean and `flutter test` must pass before the step is complete.
- All tests run on the host with `flutter test` — no device, no emulator.
- No existing data/domain files are modified.
- BrowseScreen and SettingsScreen remain stubs; full implementation is steps 7 and 8.

# Local Library — Plan 01: SystemDownloads Cleanup + Setup Screen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `SystemDownloads`, make `AppSettings.target` nullable, add a mandatory setup screen shown when no folder is configured, add the `/library` route stub and main-screen button.

**Architecture:** `CustomSafFolder?` replaces the sealed `DownloadTarget` hierarchy. A GoRouter redirect (driven by a `ChangeNotifier` in Riverpod) sends unconfigured users to `/setup`. The setup screen calls the existing `pickCustomFolder()`.

**Tech Stack:** Flutter, Riverpod 3, go_router 17, existing `saf_util`.

## Global Constraints

- Android only — no `Platform.isIOS` or iOS-specific code.
- `flutter analyze` must be clean and `flutter test` must pass after every task.
- Run tests with: `dart run tool/check.dart`
- Commit after every task.

---

### Task 1: Update `AppSettings` entity — remove `DownloadTarget` and `SystemDownloads`

**Files:**
- Modify: `lib/domain/entities.dart`
- Modify: `test/domain/entities_test.dart`

**Interfaces produced:**
```dart
class CustomSafFolder {
  final String uriString;
  final String displayName;
  const CustomSafFolder(this.uriString, this.displayName);
}

class AppSettings {
  final CustomSafFolder? target; // null = not configured
  final bool createAuthorFolder;
  final bool createSeriesFolder;
  const AppSettings({this.target, this.createAuthorFolder = false, this.createSeriesFolder = false});
  AppSettings copyWith({CustomSafFolder? target, bool clearTarget = false, bool? createAuthorFolder, bool? createSeriesFolder});
}
```

- [ ] **Step 1: Replace `lib/domain/entities.dart` entirely**

```dart
class CustomSafFolder {
  final String uriString;
  final String displayName;
  const CustomSafFolder(this.uriString, this.displayName);
}

class Catalog {
  final int id;
  final String title;
  final Uri rootUrl;
  final String protocol;

  const Catalog({
    required this.id,
    required this.title,
    required this.rootUrl,
    required this.protocol,
  });
}

class Favorite {
  final int id;
  final int catalogId;
  final Uri url;
  final String title;
  final int sortOrder;

  const Favorite({
    required this.id,
    required this.catalogId,
    required this.url,
    required this.title,
    required this.sortOrder,
  });
}

class AppSettings {
  final CustomSafFolder? target;
  final bool createAuthorFolder;
  final bool createSeriesFolder;

  const AppSettings({
    this.target,
    this.createAuthorFolder = false,
    this.createSeriesFolder = false,
  });

  AppSettings copyWith({
    CustomSafFolder? target,
    bool clearTarget = false,
    bool? createAuthorFolder,
    bool? createSeriesFolder,
  }) => AppSettings(
    target: clearTarget ? null : (target ?? this.target),
    createAuthorFolder: createAuthorFolder ?? this.createAuthorFolder,
    createSeriesFolder: createSeriesFolder ?? this.createSeriesFolder,
  );
}
```

- [ ] **Step 2: Replace `test/domain/entities_test.dart` entirely**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  group('Catalog', () {
    test('stores all fields', () {
      final c = Catalog(
        id: 1,
        title: 'Test Catalog',
        rootUrl: Uri.parse('https://example.com/opds'),
        protocol: 'opds1',
      );
      expect(c.id, 1);
      expect(c.title, 'Test Catalog');
      expect(c.rootUrl, Uri.parse('https://example.com/opds'));
      expect(c.protocol, 'opds1');
    });
  });

  group('Favorite', () {
    test('stores all fields', () {
      final f = Favorite(
        id: 2,
        catalogId: 1,
        url: Uri.parse('https://example.com/opds/sci-fi'),
        title: 'Science Fiction',
        sortOrder: 0,
      );
      expect(f.id, 2);
      expect(f.catalogId, 1);
      expect(f.url, Uri.parse('https://example.com/opds/sci-fi'));
      expect(f.title, 'Science Fiction');
      expect(f.sortOrder, 0);
    });
  });

  group('CustomSafFolder', () {
    test('stores uriString and displayName', () {
      const d = CustomSafFolder('content://com.example/tree/doc', 'My Folder');
      expect(d.uriString, 'content://com.example/tree/doc');
      expect(d.displayName, 'My Folder');
    });
  });

  group('AppSettings', () {
    test('defaults target to null and folder flags to false', () {
      const s = AppSettings();
      expect(s.target, isNull);
      expect(s.createAuthorFolder, isFalse);
      expect(s.createSeriesFolder, isFalse);
    });

    test('stores custom target and folder flags', () {
      const s = AppSettings(
        target: CustomSafFolder('content://uri', 'Folder'),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(s.target?.uriString, 'content://uri');
      expect(s.createAuthorFolder, isTrue);
      expect(s.createSeriesFolder, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const s = AppSettings(target: CustomSafFolder('u', 'F'));
      final s2 = s.copyWith(createAuthorFolder: true);
      expect(s2.createAuthorFolder, isTrue);
      expect(s2.createSeriesFolder, isFalse);
      expect(s2.target?.uriString, 'u');
    });

    test('copyWith can replace target', () {
      const s = AppSettings(createAuthorFolder: true);
      final s2 = s.copyWith(target: const CustomSafFolder('u', 'F'));
      expect(s2.target?.uriString, 'u');
      expect(s2.createAuthorFolder, isTrue);
    });

    test('copyWith with clearTarget=true sets target to null', () {
      const s = AppSettings(target: CustomSafFolder('u', 'F'));
      final s2 = s.copyWith(clearTarget: true);
      expect(s2.target, isNull);
    });
  });
}
```

- [ ] **Step 3: Run `dart run tool/check.dart`**

Expected: compilation errors from other files referencing `SystemDownloads` / `DownloadTarget`. That's fine — fix in subsequent tasks.

- [ ] **Step 4: Commit**

```powershell
git add lib/domain/entities.dart test/domain/entities_test.dart
git commit -m "refactor: remove SystemDownloads — AppSettings.target is now CustomSafFolder?"
```

---

### Task 2: Update `SharedPrefsSettingsRepository` and its tests

**Files:**
- Modify: `lib/data/shared_prefs_settings_repository.dart`
- Modify: `test/data/shared_prefs_settings_repository_test.dart`

- [ ] **Step 1: Replace `lib/data/shared_prefs_settings_repository.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';

class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _keyKind = 'download_target_kind';
  static const _keyUri = 'download_target_uri';
  static const _keyDisplayName = 'download_target_display_name';
  static const _keyAuthor = 'folder_per_author';
  static const _keySeries = 'folder_per_series';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kind = prefs.getString(_keyKind);
    final uri = prefs.getString(_keyUri);
    final displayName = prefs.getString(_keyDisplayName) ?? '';
    final target = (kind == 'custom' && uri != null)
        ? CustomSafFolder(uri, displayName)
        : null;
    return AppSettings(
      target: target,
      createAuthorFolder: prefs.getBool(_keyAuthor) ?? false,
      createSeriesFolder: prefs.getBool(_keySeries) ?? false,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final target = settings.target;
    if (target != null) {
      await prefs.setString(_keyKind, 'custom');
      await prefs.setString(_keyUri, target.uriString);
      await prefs.setString(_keyDisplayName, target.displayName);
    } else {
      await prefs.setString(_keyKind, 'none');
      await prefs.remove(_keyUri);
      await prefs.remove(_keyDisplayName);
    }
    await prefs.setBool(_keyAuthor, settings.createAuthorFolder);
    await prefs.setBool(_keySeries, settings.createSeriesFolder);
  }
}
```

- [ ] **Step 2: Replace `test/data/shared_prefs_settings_repository_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SharedPrefsSettingsRepository', () {
    test('load returns null target when no keys are set', () async {
      final repo = SharedPrefsSettingsRepository();
      final settings = await repo.load();
      expect(settings.target, isNull);
      expect(settings.createAuthorFolder, isFalse);
      expect(settings.createSeriesFolder, isFalse);
    });

    test('save and load roundtrip null target', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings());
      final loaded = await repo.load();
      expect(loaded.target, isNull);
    });

    test('save and load roundtrip CustomSafFolder', () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(target: CustomSafFolder(uri, 'Downloads')));
      final loaded = await repo.load();
      expect(loaded.target?.uriString, uri);
      expect(loaded.target?.displayName, 'Downloads');
    });

    test('switching from custom to null clears stored URI', () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(target: CustomSafFolder(uri, 'Folder')));
      await repo.save(const AppSettings());
      final loaded = await repo.load();
      expect(loaded.target, isNull);
    });

    test('createAuthorFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(createAuthorFolder: true));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isFalse);
    });

    test('createSeriesFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(createSeriesFolder: true));
      final loaded = await repo.load();
      expect(loaded.createSeriesFolder, isTrue);
      expect(loaded.createAuthorFolder, isFalse);
    });

    test('both folder flags persist when both are true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(createAuthorFolder: true, createSeriesFolder: true));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isTrue);
    });
  });
}
```

- [ ] **Step 3: Run `dart run tool/check.dart`**

- [ ] **Step 4: Commit**

```powershell
git add lib/data/shared_prefs_settings_repository.dart test/data/shared_prefs_settings_repository_test.dart
git commit -m "refactor: update settings repository — null target replaces SystemDownloads"
```

---

### Task 3: Update `providers.dart` — SettingsNotifier, downloadStorageProvider, add routerRefreshProvider

**Files:**
- Modify: `lib/ui/providers.dart`
- Modify: `test/ui/settings_notifier_test.dart`

- [ ] **Step 1: In `providers.dart`, replace `SettingsNotifier` and `downloadStorageProvider`**

Remove `setSystemDownloads()`. Update `build()` to use null target. Add `routerRefreshProvider`.

Replace the `SettingsNotifier` class and `downloadStorageProvider` with:

```dart
// Add this near the top of providers.dart (after imports):
class _RouterRefreshNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerRefreshProvider = ChangeNotifierProvider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen(settingsProvider, (_, __) => notifier.ping());
  return notifier;
});

// Replace SettingsNotifier:
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  bool permissionRevoked = false;

  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    final checker = ref.read(safPermissionCheckerProvider);
    var settings = await repo.load();
    final target = settings.target;
    if (target != null) {
      final hasPermission = await checker(target.uriString);
      if (!hasPermission) {
        settings = settings.copyWith(clearTarget: true);
        await repo.save(settings);
        permissionRevoked = true;
      }
    }
    return settings;
  }

  Future<bool> pickCustomFolder() async {
    if (!Platform.isAndroid) {
      final dirPath = await getDirectoryPath();
      if (dirPath == null) return false;
      final name = p.basename(dirPath);
      final newSettings =
          (state.value ?? const AppSettings()).copyWith(
            target: CustomSafFolder(dirPath, name.isEmpty ? dirPath : name),
          );
      await ref.read(settingsRepositoryProvider).save(newSettings);
      state = AsyncData(newSettings);
      return true;
    }
    final dir = await SafUtil().pickDirectory(
      persistablePermission: true,
      writePermission: true,
    );
    if (dir == null) return false;
    final name = dir.name.isNotEmpty ? dir.name : dir.uri;
    final newSettings =
        (state.value ?? const AppSettings()).copyWith(
          target: CustomSafFolder(dir.uri, name),
        );
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
    return true;
  }

  Future<void> setCreateAuthorFolder(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newSettings = current.copyWith(createAuthorFolder: value);
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }

  Future<void> setCreateSeriesFolder(bool value) async {
    final current = state.value;
    if (current == null) return;
    final newSettings = current.copyWith(createSeriesFolder: value);
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }
}

// Replace downloadStorageProvider:
final downloadStorageProvider = Provider<DownloadStorage?>((ref) {
  final target = ref.watch(settingsProvider).value?.target;
  return switch (target) {
    CustomSafFolder(uriString: final uri) when Platform.isAndroid =>
      SafDownloadStorage(uri),
    CustomSafFolder(uriString: final path) => FileSystemDownloadStorage(path),
    null => null,
  };
});
```

- [ ] **Step 2: Replace `test/ui/settings_notifier_test.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

class FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings;
  FakeSettingsRepository(this._settings);
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

ProviderContainer _makeContainer({
  required AppSettings initial,
  bool permissionGranted = true,
}) {
  return ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(initial)),
      safPermissionCheckerProvider.overrideWithValue((_) async => permissionGranted),
    ],
  );
}

void main() {
  test('build() loads settings — null target when none saved', () async {
    final c = _makeContainer(initial: const AppSettings());
    addTearDown(c.dispose);
    final settings = await c.read(settingsProvider.future);
    expect(settings.target, isNull);
    expect(settings.createAuthorFolder, isFalse);
  });

  test('build() reverts to null target when SAF permission is revoked', () async {
    const uri = 'content://example/tree/primary';
    final c = _makeContainer(
      initial: const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      permissionGranted: false,
    );
    addTearDown(c.dispose);
    final settings = await c.read(settingsProvider.future);
    expect(settings.target, isNull);
    expect(c.read(settingsProvider.notifier).permissionRevoked, isTrue);
  });

  test('build() keeps CustomSafFolder when permission is granted', () async {
    const uri = 'content://example/tree/primary';
    final c = _makeContainer(
      initial: const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      permissionGranted: true,
    );
    addTearDown(c.dispose);
    final settings = await c.read(settingsProvider.future);
    expect(settings.target?.uriString, uri);
    expect(c.read(settingsProvider.notifier).permissionRevoked, isFalse);
  });

  test('setCreateAuthorFolder(true) updates state and persists', () async {
    final repo = FakeSettingsRepository(const AppSettings());
    final c = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      safPermissionCheckerProvider.overrideWithValue((_) async => true),
    ]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setCreateAuthorFolder(true);
    expect(c.read(settingsProvider).value?.createAuthorFolder, isTrue);
    expect((await repo.load()).createAuthorFolder, isTrue);
  });

  test('setCreateSeriesFolder(true) updates state and persists', () async {
    final repo = FakeSettingsRepository(const AppSettings());
    final c = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      safPermissionCheckerProvider.overrideWithValue((_) async => true),
    ]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setCreateSeriesFolder(true);
    expect(c.read(settingsProvider).value?.createSeriesFolder, isTrue);
    expect((await repo.load()).createSeriesFolder, isTrue);
  });
}
```

- [ ] **Step 3: Fix remaining SystemDownloads compile errors in other test files**

In each of the following files, replace every occurrence of:
- `const AppSettings(target: SystemDownloads())` → `const AppSettings()`
- `AppSettings(target: SystemDownloads(), createAuthorFolder: true)` → `AppSettings(createAuthorFolder: true)`
- `AppSettings(target: SystemDownloads(), createSeriesFolder: true)` → `AppSettings(createSeriesFolder: true)`
- `isA<SystemDownloads>()` → `isNull`
- `state.value?.target, isA<SystemDownloads>()` → `state.value?.target, isNull`

Files to update (search for `SystemDownloads` in each):
- `test/ui/download_notifier_test.dart`
- `test/ui/book_details_sheet_test.dart`
- `test/ui/folder_download_notifier_test.dart`
- `test/domain/download_utils_test.dart`
- `test/data/book_downloader_test.dart`
- `test/data/folder_download_job_test.dart`

- [ ] **Step 4: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/settings_notifier_test.dart test/ui/download_notifier_test.dart test/ui/book_details_sheet_test.dart test/ui/folder_download_notifier_test.dart test/domain/download_utils_test.dart test/data/book_downloader_test.dart test/data/folder_download_job_test.dart
git commit -m "refactor: update providers and tests — remove SystemDownloads references"
```

---

### Task 4: Simplify `SettingsScreen` and its tests

**Files:**
- Modify: `lib/ui/settings_screen.dart`
- Modify: `test/ui/settings_screen_test.dart`

- [ ] **Step 1: Replace `lib/ui/settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';

String buildPathExample(AppSettings settings) {
  const author = 'Jane Doe';
  const series = 'Great Series';
  final folders = <String>['Downloads'];
  if (settings.createAuthorFolder) folders.add(author);
  if (settings.createSeriesFolder) folders.add(series);
  final fileParts = <String>[];
  if (!settings.createAuthorFolder) fileParts.add(author);
  if (!settings.createSeriesFolder) fileParts.add('$series #1');
  fileParts.add('Book Title');
  return '${folders.join('/')}/${fileParts.join(' - ')}.fb2';
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final ProviderSubscription<AsyncValue<AppSettings>> _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(settingsProvider, (_, next) {
      if (next is AsyncData && ref.read(settingsProvider.notifier).permissionRevoked) {
        ref.read(settingsProvider.notifier).permissionRevoked = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Custom downloads folder is no longer accessible — please select a new folder.',
            ),
          ));
        });
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => _SettingsBody(settings: settings),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final AppSettings settings;
  const _SettingsBody({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);
    return ListView(
      children: [
        ListTile(
          title: const Text('Downloads folder'),
          subtitle: settings.target != null
              ? Text('Selected: ${settings.target!.displayName}')
              : const Text('No folder selected'),
          trailing: TextButton(
            onPressed: () => notifier.pickCustomFolder(),
            child: const Text('Change…'),
          ),
        ),
        const Divider(),
        const ListTile(title: Text('File organisation')),
        CheckboxListTile(
          title: const Text('Create a folder per author'),
          value: settings.createAuthorFolder,
          onChanged: (v) => notifier.setCreateAuthorFolder(v ?? false),
        ),
        CheckboxListTile(
          title: const Text('Create a folder per series'),
          value: settings.createSeriesFolder,
          onChanged: (v) => notifier.setCreateSeriesFolder(v ?? false),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            buildPathExample(settings),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Replace `test/ui/settings_screen_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/settings_screen.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  final bool _triggerPermissionRevoked;
  FakeSettingsNotifier({required AppSettings initial, bool triggerPermissionRevoked = false})
      : _initial = initial,
        _triggerPermissionRevoked = triggerPermissionRevoked;

  @override
  Future<AppSettings> build() async {
    if (_triggerPermissionRevoked) {
      permissionRevoked = true;
      return const AppSettings();
    }
    return _initial;
  }

  @override
  Future<bool> pickCustomFolder() async {
    final newSettings =
        (state.value ?? const AppSettings()).copyWith(
          target: const CustomSafFolder('content://fake/tree', 'TestFolder'),
        );
    state = AsyncData(newSettings);
    return true;
  }

  @override
  Future<void> setCreateAuthorFolder(bool value) async {
    state = AsyncData(
      (state.value ?? const AppSettings()).copyWith(createAuthorFolder: value),
    );
  }

  @override
  Future<void> setCreateSeriesFolder(bool value) async {
    state = AsyncData(
      (state.value ?? const AppSettings()).copyWith(createSeriesFolder: value),
    );
  }
}

Widget buildApp(FakeSettingsNotifier notifier) {
  return ProviderScope(
    overrides: [settingsProvider.overrideWith(() => notifier)],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  group('buildPathExample', () {
    test('no folders: flat filename', () {
      expect(
        buildPathExample(const AppSettings()),
        'Downloads/Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('author folder enabled', () {
      expect(
        buildPathExample(const AppSettings(createAuthorFolder: true)),
        'Downloads/Jane Doe/Great Series #1 - Book Title.fb2',
      );
    });

    test('series folder enabled', () {
      expect(
        buildPathExample(const AppSettings(createSeriesFolder: true)),
        'Downloads/Great Series/Jane Doe - Book Title.fb2',
      );
    });

    test('both folders enabled', () {
      expect(
        buildPathExample(const AppSettings(createAuthorFolder: true, createSeriesFolder: true)),
        'Downloads/Jane Doe/Great Series/Book Title.fb2',
      );
    });
  });

  group('SettingsScreen', () {
    testWidgets('shows no-folder subtitle when target is null', (tester) async {
      await tester.pumpWidget(buildApp(FakeSettingsNotifier(initial: const AppSettings())));
      await tester.pumpAndSettle();
      expect(find.text('No folder selected'), findsOneWidget);
      expect(find.text('Change…'), findsOneWidget);
    });

    testWidgets('shows display name when CustomSafFolder is set', (tester) async {
      await tester.pumpWidget(buildApp(FakeSettingsNotifier(
        initial: const AppSettings(target: CustomSafFolder('content://x', 'My Folder')),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Selected: My Folder'), findsOneWidget);
    });

    testWidgets('tapping Change calls pickCustomFolder and updates subtitle', (tester) async {
      await tester.pumpWidget(buildApp(FakeSettingsNotifier(initial: const AppSettings())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change…'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: TestFolder'), findsOneWidget);
    });

    testWidgets('author checkbox toggles', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();
      expect(notifier.state.value?.createAuthorFolder, isTrue);
    });

    testWidgets('series checkbox toggles', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a folder per series'));
      await tester.pumpAndSettle();
      expect(notifier.state.value?.createSeriesFolder, isTrue);
    });

    testWidgets('path caption updates live when author checkbox changes', (tester) async {
      await tester.pumpWidget(buildApp(FakeSettingsNotifier(initial: const AppSettings())));
      await tester.pumpAndSettle();
      expect(find.text('Downloads/Jane Doe - Great Series #1 - Book Title.fb2'), findsOneWidget);
      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads/Jane Doe/Great Series #1 - Book Title.fb2'), findsOneWidget);
    });

    testWidgets('permission-revoked snackbar appears on startup', (tester) async {
      await tester.pumpWidget(buildApp(
        FakeSettingsNotifier(initial: const AppSettings(), triggerPermissionRevoked: true),
      ));
      await tester.pumpAndSettle();
      expect(
        find.text('Custom downloads folder is no longer accessible — please select a new folder.'),
        findsOneWidget,
      );
    });
  });
}
```

- [ ] **Step 3: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 4: Commit**

```powershell
git add lib/ui/settings_screen.dart test/ui/settings_screen_test.dart
git commit -m "refactor: simplify SettingsScreen — remove SystemDownloads radio buttons"
```

---

### Task 5: Add setup screen + router redirect + library button

**Files:**
- Create: `lib/ui/setup_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/ui/start_screen.dart`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the failing setup screen widget test**

Create `test/ui/setup_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/setup_screen.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  bool pickCalled = false;

  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<bool> pickCustomFolder() async {
    pickCalled = true;
    state = AsyncData(
      const AppSettings(target: CustomSafFolder('content://fake', 'Lib')),
    );
    return true;
  }
}

void main() {
  testWidgets('SetupScreen shows Pick library folder button', (tester) async {
    final notifier = _FakeSettingsNotifier();
    await tester.pumpWidget(ProviderScope(
      overrides: [settingsProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: SetupScreen()),
    ));
    expect(find.text('Pick library folder'), findsOneWidget);
    expect(find.text('Pick a folder where your books are stored'), findsOneWidget);
  });

  testWidgets('tapping Pick calls pickCustomFolder', (tester) async {
    final notifier = _FakeSettingsNotifier();
    await tester.pumpWidget(ProviderScope(
      overrides: [settingsProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: SetupScreen()),
    ));
    await tester.tap(find.text('Pick library folder'));
    await tester.pumpAndSettle();
    expect(notifier.pickCalled, isTrue);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (SetupScreen not found)**

```powershell
flutter test test/ui/setup_screen_test.dart
```

- [ ] **Step 3: Create `lib/ui/setup_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/ui/providers.dart';

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Pick a folder where your books are stored',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Pick library folder'),
                onPressed: () =>
                    ref.read(settingsProvider.notifier).pickCustomFolder(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test — expect PASS**

```powershell
flutter test test/ui/setup_screen_test.dart
```

- [ ] **Step 5: Update `lib/app.dart` — add redirect + `/setup` + `/library` routes**

Replace `lib/app.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/folder_scan_screen.dart';
import 'package:opds_browser/ui/folder_tree_screen.dart';
import 'package:opds_browser/ui/setup_screen.dart';
import 'package:opds_browser/ui/settings_screen.dart';
import 'package:opds_browser/ui/start_screen.dart';
import 'package:opds_browser/ui/providers.dart';

class OpdsBrowserApp extends ConsumerStatefulWidget {
  const OpdsBrowserApp({super.key});

  @override
  ConsumerState<OpdsBrowserApp> createState() => _OpdsBrowserAppState();
}

class _OpdsBrowserAppState extends ConsumerState<OpdsBrowserApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final refresher = ref.read(routerRefreshProvider);
    _router = GoRouter(
      refreshListenable: refresher,
      redirect: (context, state) {
        final container = ProviderScope.containerOf(context, listen: false);
        final settings = container.read(settingsProvider).value;
        if (settings == null) return null; // still loading
        if (settings.target == null && state.matchedLocation != '/setup') {
          return '/setup';
        }
        if (settings.target != null && state.matchedLocation == '/setup') {
          return '/';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, __) => const StartScreen()),
        GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
        GoRoute(
          path: '/browse',
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return BrowseScreen(
              catalogId: int.parse(params['catalogId']!),
              url: Uri.parse(params['url']!),
              navTitle: params['title'],
              inferredSeries: params['series'],
            );
          },
        ),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
          path: '/folder-scan',
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return FolderScanScreen(
              catalogId: int.parse(params['catalogId']!),
              url: params['url']!,
            );
          },
        ),
        GoRoute(path: '/folder-tree', builder: (_, __) => const FolderTreeScreen()),
        GoRoute(
          path: '/library',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Library coming soon')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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

- [ ] **Step 6: Add library `IconButton` to `lib/ui/start_screen.dart` AppBar**

In `_StartScreenContent.build()`, add to the `appBar.actions` list after the settings icon:

```dart
actions: [
  IconButton(
    icon: const Icon(Icons.local_library_outlined),
    tooltip: 'Manage local library',
    onPressed: () => context.push('/library'),
  ),
  IconButton(
    icon: const Icon(Icons.settings),
    onPressed: () => context.push('/settings'),
  ),
],
```

- [ ] **Step 7: Update `CLAUDE.md`**

In the Tech Stack table, change:
```
| Android storage | `saf_stream` + `saf_util` (SAF); MediaStore via direct Android API |
```
to:
```
| Android storage | `saf_stream` + `saf_util` (SAF only — a custom folder is always required) |
```

Remove any mention of `SystemDownloads` from the spec notes.

- [ ] **Step 8: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 9: Commit**

```powershell
git add lib/ui/setup_screen.dart lib/app.dart lib/ui/start_screen.dart CLAUDE.md test/ui/setup_screen_test.dart
git commit -m "feat: add setup screen, router redirect, library button — mandatory SAF folder"
```

# Settings + DownloadStorage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Settings screen, `DownloadStorage` abstraction, and `SafDownloadStorage` (SAF-backed for both download targets), completing step 8 of the implementation order.

**Architecture:** `DownloadStorage` interface in domain; `SafDownloadStorage` wraps `saf` package's `DocumentFile` API; `SettingsNotifier` (`AsyncNotifier`) handles persistence via `SharedPrefsSettingsRepository` and checks SAF permission on startup; `SettingsScreen` uses `ConsumerStatefulWidget` with `ref.listenManual(fireImmediately: true)` so the permission-revoked snackbar fires regardless of when the provider loaded.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifier`), `shared_preferences`, `saf ^1.0.4` (`DocumentFile` API from internal paths), `flutter_test`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/domain/entities.dart` | Modify | Add `displayName` to `CustomSafFolder`; add `AppSettings.copyWith` |
| `lib/domain/repositories.dart` | Modify | Add `DownloadStorage` interface |
| `lib/data/saf_download_storage.dart` | Create | `SafDownloadStorage` — SAF file ops via `DocumentFile` |
| `lib/data/shared_prefs_settings_repository.dart` | Modify | Persist `displayName` alongside URI |
| `lib/ui/providers.dart` | Modify | Add `safPermissionCheckerProvider`, `SettingsNotifier`, `settingsProvider`, `downloadStorageProvider` |
| `lib/ui/settings_screen.dart` | Modify | Full settings UI replacing stub |
| `test/domain/entities_test.dart` | Modify | Fix `CustomSafFolder` callsites; add `displayName` + `copyWith` tests |
| `test/data/shared_prefs_settings_repository_test.dart` | Modify | Fix callsites; add `displayName` roundtrip tests |
| `test/ui/settings_notifier_test.dart` | Create | Tests for `SettingsNotifier` with fake repo + fake permission checker |
| `test/ui/settings_screen_test.dart` | Create | Widget tests for `SettingsScreen` + unit tests for `buildPathExample` |

---

## Task 1: `CustomSafFolder.displayName` + `AppSettings.copyWith`

`CustomSafFolder` gains a required `displayName` field so the UI can show the folder name without async calls at render time. `AppSettings` gains `copyWith` so `SettingsNotifier` can produce updated values cleanly. Both are breaking changes that also require fixing existing call sites in the same commit.

**Files:**
- Modify: `test/domain/entities_test.dart`
- Modify: `lib/domain/entities.dart`
- Modify: `lib/data/shared_prefs_settings_repository.dart` (temporary fix — proper update in Task 3)

- [ ] **Step 1: Add failing tests to `test/domain/entities_test.dart`**

Replace the file's current `DownloadTarget` and `AppSettings` groups with the updated versions below. The `CustomSafFolder` tests gain a second arg; two new tests are added.

```dart
  group('DownloadTarget', () {
    test('SystemDownloads is a DownloadTarget', () {
      const d = SystemDownloads();
      expect(d, isA<DownloadTarget>());
    });

    test('CustomSafFolder stores uriString', () {
      const d = CustomSafFolder('content://com.example/tree/doc', 'doc');
      expect(d, isA<DownloadTarget>());
      expect(d.uriString, 'content://com.example/tree/doc');
    });

    test('CustomSafFolder stores displayName', () {
      const d = CustomSafFolder('content://com.example/tree/doc', 'My Downloads');
      expect(d.displayName, 'My Downloads');
    });
  });

  group('AppSettings', () {
    test('defaults createAuthorFolder and createSeriesFolder to false', () {
      const s = AppSettings(target: SystemDownloads());
      expect(s.createAuthorFolder, isFalse);
      expect(s.createSeriesFolder, isFalse);
      expect(s.target, isA<SystemDownloads>());
    });

    test('stores custom target and folder flags', () {
      const s = AppSettings(
        target: CustomSafFolder('content://uri', 'Folder'),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(s.target, isA<CustomSafFolder>());
      expect((s.target as CustomSafFolder).uriString, 'content://uri');
      expect(s.createAuthorFolder, isTrue);
      expect(s.createSeriesFolder, isTrue);
    });

    test('copyWith creates updated copy preserving unchanged fields', () {
      const s = AppSettings(target: SystemDownloads());
      final s2 = s.copyWith(createAuthorFolder: true);
      expect(s2.createAuthorFolder, isTrue);
      expect(s2.createSeriesFolder, isFalse);
      expect(s2.target, isA<SystemDownloads>());
    });

    test('copyWith can change target', () {
      const s = AppSettings(target: SystemDownloads(), createAuthorFolder: true);
      final s2 = s.copyWith(target: const CustomSafFolder('u', 'F'));
      expect(s2.target, isA<CustomSafFolder>());
      expect(s2.createAuthorFolder, isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/domain/entities_test.dart
```

Expected: compile error — `CustomSafFolder` called with wrong arity.

- [ ] **Step 3: Update `lib/domain/entities.dart`**

Replace the entire file:

```dart
sealed class DownloadTarget {
  const DownloadTarget();
}

class SystemDownloads extends DownloadTarget {
  const SystemDownloads();
}

class CustomSafFolder extends DownloadTarget {
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
  final DownloadTarget target;
  final bool createAuthorFolder;
  final bool createSeriesFolder;

  const AppSettings({
    required this.target,
    this.createAuthorFolder = false,
    this.createSeriesFolder = false,
  });

  AppSettings copyWith({
    DownloadTarget? target,
    bool? createAuthorFolder,
    bool? createSeriesFolder,
  }) =>
      AppSettings(
        target: target ?? this.target,
        createAuthorFolder: createAuthorFolder ?? this.createAuthorFolder,
        createSeriesFolder: createSeriesFolder ?? this.createSeriesFolder,
      );
}
```

- [ ] **Step 4: Fix compile errors in `lib/data/shared_prefs_settings_repository.dart`**

`load()` constructs `CustomSafFolder(uri, ...)`. For now, pass an empty string as the display name — Task 3 will make it read from prefs.

In `load()`, find the line:
```dart
    final target = (kind == 'custom' && uri != null)
        ? CustomSafFolder(uri)
        : const SystemDownloads();
```

Replace with:
```dart
    final target = (kind == 'custom' && uri != null)
        ? CustomSafFolder(uri, '')
        : const SystemDownloads();
```

- [ ] **Step 5: Run tests to confirm they pass**

```powershell
flutter test test/domain/entities_test.dart
```

Expected: all pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/domain/entities.dart lib/data/shared_prefs_settings_repository.dart test/domain/entities_test.dart
git commit -m "feat(domain): add CustomSafFolder.displayName and AppSettings.copyWith"
```

---

## Task 2: `DownloadStorage` interface

Adds the storage abstraction to the domain layer. No runtime logic — just an interface.

**Files:**
- Modify: `lib/domain/repositories.dart`

- [ ] **Step 1: Add `DownloadStorage` to `lib/domain/repositories.dart`**

Append after the `SettingsRepository` interface:

```dart
abstract interface class DownloadStorage {
  /// Returns true if a file with this path already exists.
  Future<bool> exists(List<String> pathSegments, String fileName);

  /// Streams [bytes] into the file, creating intermediate folders.
  /// Returns an opaque locator usable by open_filex (content URI string).
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  );
}
```

- [ ] **Step 2: Run analysis to confirm no errors**

```powershell
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Commit**

```powershell
git add lib/domain/repositories.dart
git commit -m "feat(domain): add DownloadStorage interface"
```

---

## Task 3: `SharedPrefsSettingsRepository` — persist `displayName`

The repository currently stores only the URI for `CustomSafFolder`. Add a new prefs key `download_target_display_name`.

**Files:**
- Modify: `test/data/shared_prefs_settings_repository_test.dart`
- Modify: `lib/data/shared_prefs_settings_repository.dart`

- [ ] **Step 1: Update `test/data/shared_prefs_settings_repository_test.dart`**

Update existing `CustomSafFolder` call sites (which currently use one arg) and update the roundtrip test to also assert `displayName`. The full updated test file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SharedPrefsSettingsRepository', () {
    test('load returns defaults when no keys are set', () async {
      final repo = SharedPrefsSettingsRepository();
      final settings = await repo.load();
      expect(settings.target, isA<SystemDownloads>());
      expect(settings.createAuthorFolder, isFalse);
      expect(settings.createSeriesFolder, isFalse);
    });

    test('save and load roundtrip SystemDownloads', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(target: SystemDownloads()));
      final loaded = await repo.load();
      expect(loaded.target, isA<SystemDownloads>());
    });

    test('save and load roundtrip CustomSafFolder — uri and displayName',
        () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      );
      final loaded = await repo.load();
      expect(loaded.target, isA<CustomSafFolder>());
      expect((loaded.target as CustomSafFolder).uriString, uri);
      expect((loaded.target as CustomSafFolder).displayName, 'Downloads');
    });

    test('switching from custom back to system clears stored URI and displayName',
        () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(target: CustomSafFolder(uri, 'Folder')),
      );
      await repo.save(const AppSettings(target: SystemDownloads()));
      final loaded = await repo.load();
      expect(loaded.target, isA<SystemDownloads>());
    });

    test('createAuthorFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
      ));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isFalse);
    });

    test('createSeriesFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(
        target: SystemDownloads(),
        createSeriesFolder: true,
      ));
      final loaded = await repo.load();
      expect(loaded.createSeriesFolder, isTrue);
      expect(loaded.createAuthorFolder, isFalse);
    });

    test('both folder flags persist when both are true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
        createSeriesFolder: true,
      ));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm roundtrip test fails**

```powershell
flutter test test/data/shared_prefs_settings_repository_test.dart
```

Expected: `save and load roundtrip CustomSafFolder — uri and displayName` FAILS (loaded `displayName` is `''` not `'Downloads'`).

- [ ] **Step 3: Update `lib/data/shared_prefs_settings_repository.dart`**

Replace the entire file:

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
    final kind = prefs.getString(_keyKind) ?? 'system';
    final uri = prefs.getString(_keyUri);
    final displayName = prefs.getString(_keyDisplayName) ?? '';
    final target = (kind == 'custom' && uri != null)
        ? CustomSafFolder(uri, displayName)
        : const SystemDownloads();
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
    if (target is CustomSafFolder) {
      await prefs.setString(_keyKind, 'custom');
      await prefs.setString(_keyUri, target.uriString);
      await prefs.setString(_keyDisplayName, target.displayName);
    } else {
      await prefs.setString(_keyKind, 'system');
      await prefs.remove(_keyUri);
      await prefs.remove(_keyDisplayName);
    }
    await prefs.setBool(_keyAuthor, settings.createAuthorFolder);
    await prefs.setBool(_keySeries, settings.createSeriesFolder);
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/data/shared_prefs_settings_repository_test.dart
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/shared_prefs_settings_repository.dart test/data/shared_prefs_settings_repository_test.dart
git commit -m "feat(data): persist CustomSafFolder.displayName in shared_prefs"
```

---

## Task 4: `SafDownloadStorage`

SAF-backed implementation of `DownloadStorage`. Both download targets use this once a tree URI is available. No host-side unit tests — it is a thin wrapper over SAF platform channel calls that cannot run without a device.

**Files:**
- Create: `lib/data/saf_download_storage.dart`

- [ ] **Step 1: Create `lib/data/saf_download_storage.dart`**

```dart
import 'dart:typed_data';

import 'package:opds_browser/domain/repositories.dart';
import 'package:saf/src/storage_access_framework/api.dart' as safApi;
import 'package:saf/src/storage_access_framework/document_file.dart';

class SafDownloadStorage implements DownloadStorage {
  final String _treeUriString;
  SafDownloadStorage(this._treeUriString);

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async {
    var dir = await DocumentFile.fromTreeUri(Uri.parse(_treeUriString));
    if (dir == null) return false;
    for (final segment in pathSegments) {
      dir = await safApi.findFile(dir!.uri, segment);
      if (dir == null) return false;
    }
    return await safApi.findFile(dir!.uri, fileName) != null;
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    var dir = await DocumentFile.fromTreeUri(Uri.parse(_treeUriString));
    for (final segment in pathSegments) {
      final existing = await safApi.findFile(dir!.uri, segment);
      dir = existing ?? await safApi.createDirectory(dir!.uri, segment);
    }
    final buffer = await bytes.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final file = await safApi.createFileAsBytes(
      dir!.uri,
      mimeType: 'application/octet-stream',
      displayName: fileName,
      content: Uint8List.fromList(buffer),
    );
    return file!.uri.toString();
  }
}
```

- [ ] **Step 2: Run analysis**

```powershell
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Commit**

```powershell
git add lib/data/saf_download_storage.dart
git commit -m "feat(data): add SafDownloadStorage using saf DocumentFile API"
```

---

## Task 5: `SettingsNotifier` + providers

Adds state management for settings: loads on startup with SAF permission check, and exposes methods for UI to call.

**Files:**
- Create: `test/ui/settings_notifier_test.dart`
- Modify: `lib/ui/providers.dart`

- [ ] **Step 1: Create `test/ui/settings_notifier_test.dart`**

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
  return ProviderContainer(overrides: [
    settingsRepositoryProvider
        .overrideWithValue(FakeSettingsRepository(initial)),
    safPermissionCheckerProvider
        .overrideWithValue((_) async => permissionGranted),
  ]);
}

void main() {
  test('build() loads settings from repository', () async {
    final c = _makeContainer(
      initial: const AppSettings(target: SystemDownloads()),
    );
    addTearDown(c.dispose);

    final settings = await c.read(settingsProvider.future);
    expect(settings.target, isA<SystemDownloads>());
    expect(settings.createAuthorFolder, isFalse);
  });

  test('build() reverts to SystemDownloads when permission is revoked',
      () async {
    const uri = 'content://example/tree/primary';
    final c = _makeContainer(
      initial: const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      permissionGranted: false,
    );
    addTearDown(c.dispose);

    final settings = await c.read(settingsProvider.future);
    expect(settings.target, isA<SystemDownloads>());
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
    expect(settings.target, isA<CustomSafFolder>());
    expect(c.read(settingsProvider.notifier).permissionRevoked, isFalse);
  });

  test('setSystemDownloads() updates state and persists', () async {
    const uri = 'content://example/tree/primary';
    final repo =
        FakeSettingsRepository(const AppSettings(target: CustomSafFolder(uri, 'D')));
    final c = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      safPermissionCheckerProvider.overrideWithValue((_) async => true),
    ]);
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setSystemDownloads();

    expect(c.read(settingsProvider).value?.target, isA<SystemDownloads>());
    expect((await repo.load()).target, isA<SystemDownloads>());
  });

  test('setCreateAuthorFolder(true) updates state and persists', () async {
    final repo =
        FakeSettingsRepository(const AppSettings(target: SystemDownloads()));
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
    final repo =
        FakeSettingsRepository(const AppSettings(target: SystemDownloads()));
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

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/ui/settings_notifier_test.dart
```

Expected: compile error — `settingsProvider`, `safPermissionCheckerProvider` not found.

- [ ] **Step 3: Add providers to `lib/ui/providers.dart`**

Add these imports at the top of the existing imports block:

```dart
import 'package:saf/saf.dart';
import 'package:saf/src/storage_access_framework/api.dart' as safApi;
import 'package:saf/src/storage_access_framework/document_file.dart';
import 'package:opds_browser/data/saf_download_storage.dart';
```

Then append the following after the existing `settingsRepositoryProvider`:

```dart
final safPermissionCheckerProvider =
    Provider<Future<bool> Function(String)>((ref) {
  return (uri) async =>
      (await Saf.isPersistedPermissionDirectoryFor(uri)) ?? false;
});

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  bool permissionRevoked = false;

  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    final checker = ref.read(safPermissionCheckerProvider);
    var settings = await repo.load();
    if (settings.target is CustomSafFolder) {
      final uri = (settings.target as CustomSafFolder).uriString;
      final hasPermission = await checker(uri);
      if (!hasPermission) {
        settings = settings.copyWith(target: const SystemDownloads());
        await repo.save(settings);
        permissionRevoked = true;
      }
    }
    return settings;
  }

  Future<bool> pickCustomFolder() async {
    final uri = await safApi.openDocumentTree();
    if (uri == null) return false;
    final doc = await DocumentFile.fromTreeUri(Uri.parse(uri));
    final name = doc?.name ?? uri;
    final newSettings = (state.valueOrNull ??
            const AppSettings(target: SystemDownloads()))
        .copyWith(target: CustomSafFolder(uri, name));
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
    return true;
  }

  Future<void> setSystemDownloads() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final newSettings = current.copyWith(target: const SystemDownloads());
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }

  Future<void> setCreateAuthorFolder(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final newSettings = current.copyWith(createAuthorFolder: value);
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }

  Future<void> setCreateSeriesFolder(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final newSettings = current.copyWith(createSeriesFolder: value);
    await ref.read(settingsRepositoryProvider).save(newSettings);
    state = AsyncData(newSettings);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final downloadStorageProvider = Provider<DownloadStorage?>((ref) {
  final target = ref.watch(settingsProvider).valueOrNull?.target;
  return switch (target) {
    CustomSafFolder(uriString: final uri) => SafDownloadStorage(uri),
    _ => null,
  };
});
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/ui/settings_notifier_test.dart
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/settings_notifier_test.dart
git commit -m "feat(ui): add SettingsNotifier, settingsProvider, downloadStorageProvider"
```

---

## Task 6: `SettingsScreen`

Replaces the "coming soon" stub with the full settings UI. Uses `ConsumerStatefulWidget` + `ref.listenManual(fireImmediately: true)` so the permission-revoked snackbar fires even when `settingsProvider` was already loaded before the screen opened.

**Files:**
- Create: `test/ui/settings_screen_test.dart`
- Modify: `lib/ui/settings_screen.dart`

- [ ] **Step 1: Create `test/ui/settings_screen_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/settings_screen.dart';

// ── Fake notifier ────────────────────────────────────────────────────────────

class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  final bool _triggerPermissionRevoked;

  FakeSettingsNotifier({
    required AppSettings initial,
    bool triggerPermissionRevoked = false,
  })  : _initial = initial,
        _triggerPermissionRevoked = triggerPermissionRevoked;

  @override
  Future<AppSettings> build() async {
    if (_triggerPermissionRevoked) {
      permissionRevoked = true;
      return const AppSettings(target: SystemDownloads());
    }
    return _initial;
  }

  @override
  Future<bool> pickCustomFolder() async {
    final newSettings = (state.valueOrNull ??
            const AppSettings(target: SystemDownloads()))
        .copyWith(
      target: const CustomSafFolder('content://fake/tree', 'TestFolder'),
    );
    state = AsyncData(newSettings);
    return true;
  }

  @override
  Future<void> setSystemDownloads() async {
    state = AsyncData(
      (state.valueOrNull ?? const AppSettings(target: SystemDownloads()))
          .copyWith(target: const SystemDownloads()),
    );
  }

  @override
  Future<void> setCreateAuthorFolder(bool value) async {
    state = AsyncData(
      (state.valueOrNull ?? const AppSettings(target: SystemDownloads()))
          .copyWith(createAuthorFolder: value),
    );
  }

  @override
  Future<void> setCreateSeriesFolder(bool value) async {
    state = AsyncData(
      (state.valueOrNull ?? const AppSettings(target: SystemDownloads()))
          .copyWith(createSeriesFolder: value),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

Widget buildApp(FakeSettingsNotifier notifier) {
  return ProviderScope(
    overrides: [settingsProvider.overrideWith(() => notifier)],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('buildPathExample', () {
    test('no folders: filename directly under Downloads', () {
      const s = AppSettings(target: SystemDownloads());
      expect(
        buildPathExample(s),
        'Downloads/Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('author folder enabled', () {
      const s = AppSettings(
          target: SystemDownloads(), createAuthorFolder: true);
      expect(
        buildPathExample(s),
        'Downloads/Jane Doe/Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('series folder enabled', () {
      const s = AppSettings(
          target: SystemDownloads(), createSeriesFolder: true);
      expect(
        buildPathExample(s),
        'Downloads/Great Series/Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('both folders enabled', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(
        buildPathExample(s),
        'Downloads/Jane Doe/Great Series/Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });
  });

  group('SettingsScreen', () {
    testWidgets('renders both radios with System Downloads selected by default',
        (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(target: SystemDownloads()),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      expect(find.text('System Downloads folder'), findsOneWidget);
      expect(find.text('Custom folder…'), findsOneWidget);
      expect(find.text('Tap to select a folder'), findsOneWidget);
    });

    testWidgets('shows display name subtitle when CustomSafFolder is set',
        (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(
          target: CustomSafFolder('content://x', 'My Folder'),
        ),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      expect(find.text('Selected: My Folder'), findsOneWidget);
    });

    testWidgets('tapping Custom folder tile calls pickCustomFolder and updates subtitle',
        (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(target: SystemDownloads()),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom folder…'));
      await tester.pumpAndSettle();

      expect(find.text('Selected: TestFolder'), findsOneWidget);
    });

    testWidgets('tapping System Downloads radio calls setSystemDownloads',
        (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(
            target: CustomSafFolder('content://x', 'My Folder')),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('System Downloads folder'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to select a folder'), findsOneWidget);
    });

    testWidgets('author checkbox toggles on and off', (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(target: SystemDownloads()),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();

      expect(notifier.state.value?.createAuthorFolder, isTrue);
    });

    testWidgets('series checkbox toggles on and off', (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(target: SystemDownloads()),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create a folder per series'));
      await tester.pumpAndSettle();

      expect(notifier.state.value?.createSeriesFolder, isTrue);
    });

    testWidgets('path caption updates live when author checkbox changes',
        (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(target: SystemDownloads()),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      expect(
        find.text('Downloads/Jane Doe - Great Series #1 - Book Title.fb2'),
        findsOneWidget,
      );

      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Downloads/Jane Doe/Jane Doe - Great Series #1 - Book Title.fb2'),
        findsOneWidget,
      );
    });

    testWidgets('permission-revoked snackbar appears on startup', (tester) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(target: SystemDownloads()),
        triggerPermissionRevoked: true,
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Custom downloads folder is no longer accessible — reverted to system Downloads.',
        ),
        findsOneWidget,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
flutter test test/ui/settings_screen_test.dart
```

Expected: compile error — `buildPathExample` not found, `SettingsScreen` is still a stub.

- [ ] **Step 3: Implement `lib/ui/settings_screen.dart`**

Replace the entire file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';

String buildPathExample(AppSettings settings) {
  const author = 'Jane Doe';
  const series = 'Great Series';
  const fileName = 'Jane Doe - Great Series #1 - Book Title.fb2';
  final parts = <String>['Downloads'];
  if (settings.createAuthorFolder) parts.add(author);
  if (settings.createSeriesFolder) parts.add(series);
  return '${parts.join('/')}/$fileName';
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
      if (next is AsyncData) {
        final notifier = ref.read(settingsProvider.notifier);
        if (notifier.permissionRevoked) {
          notifier.permissionRevoked = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Custom downloads folder is no longer accessible'
                  ' — reverted to system Downloads.',
                ),
              ),
            );
          });
        }
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
    final isCustom = settings.target is CustomSafFolder;

    return ListView(
      children: [
        const ListTile(title: Text('Downloads folder')),
        RadioListTile<bool>(
          title: const Text('System Downloads folder'),
          value: false,
          groupValue: isCustom,
          onChanged: (_) => notifier.setSystemDownloads(),
        ),
        ListTile(
          leading: Radio<bool>(
            value: true,
            groupValue: isCustom,
            onChanged: (_) => notifier.pickCustomFolder(),
          ),
          title: const Text('Custom folder…'),
          subtitle: isCustom
              ? Text(
                  'Selected: ${(settings.target as CustomSafFolder).displayName}',
                )
              : const Text('Tap to select a folder'),
          onTap: () => notifier.pickCustomFolder(),
        ),
        const Divider(),
        const ListTile(title: Text('File organization')),
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

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
flutter test test/ui/settings_screen_test.dart
```

Expected: all 12 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/settings_screen.dart test/ui/settings_screen_test.dart
git commit -m "feat(ui): implement SettingsScreen with SAF folder picker and file organization"
```

---

## Task 7: Quality Gate

Run the full suite and fix anything that comes up.

**Files:** (none expected — this is a verification step)

- [ ] **Step 1: Run full quality gate**

```powershell
dart run tool/check.dart
```

Expected output ends with:
```
flutter analyze ... No issues found!
flutter test   ... All tests passed!
```

- [ ] **Step 2: Fix any issues**

If `flutter analyze` reports issues, fix them and re-run. Common causes:
- `strict-inference`: add explicit type annotations where Dart can't infer
- Unused imports: remove
- `strict-casts`: replace `as T` with an `is T` guard

- [ ] **Step 3: Commit if any fixes were needed**

```powershell
git add -A
git commit -m "fix: resolve analysis issues from step 8"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| `DownloadStorage` interface (§10.3) | Task 2 |
| `CustomSafFolder.displayName` + `AppSettings.copyWith` | Task 1 |
| `SafDownloadStorage` — exists + write via SAF (§10.3) | Task 4 |
| `SharedPrefsSettingsRepository` persists displayName | Task 3 |
| `safPermissionCheckerProvider` (injectable for tests) | Task 5 |
| `SettingsNotifier` — load, permission check, revert on revoke | Task 5 |
| `settingsProvider` + `downloadStorageProvider` | Task 5 |
| `SettingsScreen` — two-radio target picker, two checkboxes, path caption | Task 6 |
| Permission-revoked snackbar with `fireImmediately: true` | Task 6 |
| `buildPathExample` pure function (all 4 checkbox combos tested) | Task 6 |
| `entities_test.dart` updated for new `CustomSafFolder` arity | Task 1 |
| `shared_prefs_settings_repository_test.dart` updated + extended | Task 3 |
| `settings_notifier_test.dart` — 6 tests | Task 5 |
| `settings_screen_test.dart` — 12 tests | Task 6 |
| Quality gate passes | Task 7 |

**Placeholder scan:** None found.

**Type consistency:**
- `CustomSafFolder(uriString, displayName)` — two-arg form used consistently from Task 1 onward
- `AppSettings.copyWith` defined Task 1, used in Tasks 5–6
- `safPermissionCheckerProvider` typed `Provider<Future<bool> Function(String)>` — matched in Task 5 notifier and test overrides
- `downloadStorageProvider` returns `DownloadStorage?` — `SafDownloadStorage` implements `DownloadStorage` ✓
- `buildPathExample(AppSettings)` defined and exported in `settings_screen.dart`, imported in test ✓

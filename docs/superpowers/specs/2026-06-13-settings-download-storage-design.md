# Step 8 Design: Settings + DownloadStorage

**Date:** 2026-06-13
**Status:** Approved
**Spec reference:** §8.3, §10

---

## Context

Implementation order step 8. Steps 1–7 are complete. Already in place:
- `AppSettings`, `DownloadTarget`, `SystemDownloads`, `CustomSafFolder` entities
- `SettingsRepository` interface and `SharedPrefsSettingsRepository` implementation (fully tested)
- `settingsRepositoryProvider` wired in `providers.dart`
- `SettingsScreen` stub ("coming soon")
- `saf ^1.0.4` in deps

Remaining for this step: `DownloadStorage` interface + `SafDownloadStorage`, full `SettingsScreen` UI, `SettingsNotifier`, and permission verification on startup.

---

## Key decisions

### MediaStore deferred

`shared_storage` was discontinued; `saf ^1.0.4` was substituted. `saf` covers SAF only, not MediaStore. MediaStore (`MediaStore.Downloads`, API 29+) is **deferred** to a later step — both download targets use SAF in this implementation.

### System Downloads → one-time SAF picker on first download

The "System Downloads folder" radio in Settings does NOT trigger a picker immediately. The distinction from "Custom folder" is only presentational. When the user actually triggers a download and `target == SystemDownloads()` with no URI stored, Step 9 will open the picker. The `downloadStorageProvider` returns `null` in this case, and Step 9 handles it.

The "Custom folder" radio opens the SAF picker immediately on selection, as per spec §8.3.

### `saf` package capabilities confirmed

`openDocumentTree()` (in `saf/src/storage_access_framework/api.dart`) returns the selected tree URI string directly. `DocumentFile.fromTreeUri()`, `findFile()`, `createDirectory()`, and `createFileAsBytes(Uint8List)` cover all storage operations needed.

---

## Section 1: Domain layer

### `DownloadStorage` interface

Added to `lib/domain/repositories.dart`:

```dart
abstract interface class DownloadStorage {
  /// Returns true if a file with this relative path already exists.
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

### `CustomSafFolder` update

`displayName` field added so the UI can show the selected folder name without an async call at render time:

```dart
class CustomSafFolder extends DownloadTarget {
  final String uriString;
  final String displayName;
  const CustomSafFolder(this.uriString, this.displayName);
}
```

`SharedPrefsSettingsRepository` gains key `download_target_display_name` to persist the display name alongside the URI. Existing tests updated; roundtrip test gains a `displayName` assertion.

### `AppSettings.copyWith`

`SettingsNotifier` methods need to produce updated `AppSettings` values. Add `copyWith` to `AppSettings` in `lib/domain/entities.dart`:

```dart
AppSettings copyWith({
  DownloadTarget? target,
  bool? createAuthorFolder,
  bool? createSeriesFolder,
}) => AppSettings(
  target: target ?? this.target,
  createAuthorFolder: createAuthorFolder ?? this.createAuthorFolder,
  createSeriesFolder: createSeriesFolder ?? this.createSeriesFolder,
);
```

---

## Section 2: Data layer

### `SafDownloadStorage` (`lib/data/saf_download_storage.dart`)

Single implementation for both `SystemDownloads` and `CustomSafFolder` targets (once a URI is available).

```dart
class SafDownloadStorage implements DownloadStorage {
  final String _treeUriString;
  SafDownloadStorage(this._treeUriString);

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async {
    var dir = await DocumentFile.fromTreeUri(Uri.parse(_treeUriString));
    if (dir == null) return false;
    for (final segment in pathSegments) {
      dir = await dir!.findFile(segment);
      if (dir == null) return false;
    }
    return await dir!.findFile(fileName) != null;
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    var dir = await DocumentFile.fromTreeUri(Uri.parse(_treeUriString));
    for (final segment in pathSegments) {
      final existing = await dir!.findFile(segment);
      dir = existing ?? await dir.createDirectory(segment);
    }
    final buffer = await bytes.fold<List<int>>([], (a, b) => a..addAll(b));
    final file = await dir!.createFileAsBytes(
      mimeType: 'application/octet-stream',
      displayName: fileName,
      content: Uint8List.fromList(buffer),
    );
    return file!.uri.toString();
  }
}
```

**MIME type:** `application/octet-stream` prevents Android from appending an extension to the display name.

**No host-side unit tests** for `SafDownloadStorage` — it is a thin wrapper over SAF platform channel calls that cannot run on a Flutter host test environment. An `InMemoryDownloadStorage` fake will be created in Step 9 for download engine tests and widget tests.

---

## Section 3: State layer

### `safPermissionCheckerProvider` (added to `lib/ui/providers.dart`)

The permission check calls `Saf.isPersistedPermissionDirectoryFor()`, a platform channel call that throws `MissingPluginException` in host tests. Make it injectable:

```dart
final safPermissionCheckerProvider = Provider<Future<bool> Function(String)>(
  (ref) => (uri) async =>
      (await Saf.isPersistedPermissionDirectoryFor(uri)) ?? false,
);
```

Tests override this with a simple `(uri) async => true/false` function.

### `SettingsNotifier` (added to `lib/ui/providers.dart`)

`AsyncNotifier<AppSettings>`.

**`build()`:**
1. Load settings from `settingsRepositoryProvider`.
2. If target is `CustomSafFolder`, call `ref.read(safPermissionCheckerProvider)(uriString)`.
3. If permission is revoked → silently revert to `SystemDownloads()`, save, set `permissionRevoked = true` on the notifier.

**Methods:**
- `pickCustomFolder()` → `Future<bool>`: calls `openDocumentTree()` from `saf`; on non-null result, fetches display name via `DocumentFile.fromTreeUri(uri).name`, updates state to `CustomSafFolder(uri, name)`, saves. Returns true if folder was picked, false if cancelled.
- `setSystemDownloads()`: sets target to `SystemDownloads()`, saves.
- `setCreateAuthorFolder(bool)` / `setCreateSeriesFolder(bool)`: update flag, save.

**`permissionRevoked` flag:** a plain `bool` field on the notifier (not part of `AppSettings`). The SettingsScreen listens for it with `ref.listen` and shows a snackbar once, then resets it.

### Providers added

```dart
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final downloadStorageProvider = Provider<DownloadStorage?>((ref) {
  final target = ref.watch(settingsProvider).valueOrNull?.target;
  return switch (target) {
    CustomSafFolder(uriString: final uri) => SafDownloadStorage(uri),
    _ => null, // SystemDownloads or not yet loaded; Step 9 handles null
  };
});
```

---

## Section 4: SettingsScreen UI

`lib/ui/settings_screen.dart` — replaces the stub.

```
Scaffold
  AppBar: title "Settings"
  Body: ListView
    ListTile (header): "Downloads folder"
    RadioListTile<DownloadTarget>
      value: SystemDownloads()
      title: "System Downloads folder"
      onChanged: notifier.setSystemDownloads()
    RadioListTile<DownloadTarget>
      value: CustomSafFolder sentinel
      title: "Custom folder…"
      subtitle: "Selected: <displayName>"   ← when CustomSafFolder stored
                "Tap to select a folder"    ← when not yet set
      onChanged: notifier.pickCustomFolder()
    Divider
    ListTile (header): "File organization"
    CheckboxListTile "Create a folder per author"
      onChanged: notifier.setCreateAuthorFolder(val)
    CheckboxListTile "Create a folder per series"
      onChanged: notifier.setCreateSeriesFolder(val)
    Padding > Text (caption, live-updated path example)
```

**Path caption** — top-level pure function `buildPathExample(AppSettings) → String` in `lib/ui/settings_screen.dart` (exported for testing):

```
Downloads/[Jane Doe/][Great Series/]Jane Doe - Great Series #1 - Book Title.fb2
```

Folder segments appear only when the corresponding checkbox is on.

**Permission-revoked snackbar** — `SettingsScreen` must be a `ConsumerStatefulWidget`. In `initState`, register with `ref.listenManual(settingsProvider, ..., fireImmediately: true)`. The `fireImmediately: true` flag fires the callback with the *current* state immediately, so the snackbar appears whether the provider loaded before or after the screen opened:

```dart
@override
void initState() {
  super.initState();
  ref.listenManual(settingsProvider, (_, next) {
    if (next is AsyncData) {
      final notifier = ref.read(settingsProvider.notifier);
      if (notifier.permissionRevoked) {
        notifier.permissionRevoked = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Custom downloads folder is no longer accessible — reverted to system Downloads.',
            ),
          ));
        });
      }
    }
  }, fireImmediately: true);
}
```

Without `fireImmediately: true`, if `settingsProvider` is already in `AsyncData` when the screen opens (a different widget watched it earlier), the `AsyncLoading → AsyncData` transition already happened and `ref.listen` never fires — the snackbar would be silently lost.

**Radio grouping note:** `RadioListTile` requires a comparable group value. Because `SystemDownloads` and `CustomSafFolder` have different types (and `CustomSafFolder` carries state that varies), the radio group value is `settings.target is CustomSafFolder` (bool) rather than the target itself, avoiding equality issues.

---

## Tests

### `test/data/shared_prefs_settings_repository_test.dart`
- Update `CustomSafFolder` call sites to include `displayName`.
- Add: roundtrip test verifies `displayName` is saved and loaded.
- Add: switching to custom then back to system clears display name key.

### `test/ui/settings_screen_test.dart` (new)

Widget tests cannot call `pickCustomFolder()` (it calls SAF platform code). Override `settingsProvider` with a `FakeSettingsNotifier` that replaces both `build()` and `pickCustomFolder()`:

```dart
class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  FakeSettingsNotifier(this._initial);

  @override
  Future<AppSettings> build() async => _initial; // no SAF call

  @override
  Future<bool> pickCustomFolder() async {
    state = AsyncData(state.value!.copyWith(
      target: const CustomSafFolder('content://fake/tree', 'Downloads'),
    ));
    return true;
  }
}
```

Wire it up: `settingsProvider.overrideWith(() => FakeSettingsNotifier(initialSettings))`.

- Test: both radios render; current target is reflected.
- Test: tapping "Custom folder" radio triggers `FakeSettingsNotifier.pickCustomFolder()`; subtitle updates to show display name.
- Test: tapping "System Downloads" radio calls `setSystemDownloads()`.
- Test: author checkbox toggles; series checkbox toggles.
- Test: path caption updates when checkboxes change.
- Test: permission-revoked snackbar appears — set `notifier.permissionRevoked = true` on the fake notifier before pump, verify snackbar text after `pumpAndSettle()`.

### `test/ui/settings_notifier_test.dart` (new)
Override both `settingsRepositoryProvider` (fake) and `safPermissionCheckerProvider` (inline function):

```dart
settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(...)),
safPermissionCheckerProvider.overrideWithValue((uri) async => false), // simulate revoked
```

- Test: `build()` loads settings correctly.
- Test: `setSystemDownloads()` saves and updates state.
- Test: `setCreateAuthorFolder(true)` saves and updates state.
- Test: permission revoked → state reverts to `SystemDownloads`, `notifier.permissionRevoked` is true (use `safPermissionCheckerProvider` override returning `false`).
  *(The `pickCustomFolder()` method cannot be unit-tested — it calls platform SAF code.)*

### `test/ui/settings_screen_test.dart` — pure function
- `buildPathExample` for all four checkbox combinations.

---

## What is NOT in this step

- The SAF picker triggered by a first download with `SystemDownloads` selected — Step 9.
- `InMemoryDownloadStorage` fake — Step 9 (created when it's first needed by download tests).
- MediaStore implementation — future step.

---

## Files changed

| File | Change |
|------|--------|
| `lib/domain/entities.dart` | Add `displayName` to `CustomSafFolder`; add `AppSettings.copyWith` |
| `lib/domain/repositories.dart` | Add `DownloadStorage` interface |
| `lib/data/saf_download_storage.dart` | New: `SafDownloadStorage` |
| `lib/data/shared_prefs_settings_repository.dart` | Persist `displayName` |
| `lib/ui/providers.dart` | Add `safPermissionCheckerProvider`, `SettingsNotifier`, `settingsProvider`, `downloadStorageProvider` |
| `lib/ui/settings_screen.dart` | Full implementation (replaces stub) |
| `test/domain/entities_test.dart` | Update `CustomSafFolder` construction to include `displayName` |
| `test/data/shared_prefs_settings_repository_test.dart` | Update + extend |
| `test/ui/settings_notifier_test.dart` | New |
| `test/ui/settings_screen_test.dart` | New |

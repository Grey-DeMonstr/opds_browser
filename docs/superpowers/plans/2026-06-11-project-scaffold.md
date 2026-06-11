# Project Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an Android-only Flutter project skeleton that compiles, analyzes clean under strict lints, and passes a green `make check` — the known-good baseline for all later steps.

**Architecture:** A single Flutter package restructured into `lib/domain`, `lib/data`, `lib/ui` (placeholders for now) with a minimal `app.dart`/`main.dart`. All §2 dependencies are declared up front via `flutter pub add`. A cross-platform `tool/check.dart` runs `flutter analyze` + `flutter test`; a thin `Makefile` wraps it. No business logic yet.

**Tech Stack:** Flutter (latest stable, Dart null-safety), `flutter_lints` with strict analyzer modes, Android `minSdk 29`, `applicationId monster.greyde.opds_browser`. Development is Windows-native.

**Reference spec:** [`docs/superpowers/specs/2026-06-11-project-scaffold-design.md`](../specs/2026-06-11-project-scaffold-design.md)

---

## Pre-flight: verify the toolchain (Windows host)

Do this once before Task 1. Not a commit — just confirm the environment.

- [ ] **Confirm Flutter + Android toolchain are healthy**

Run: `flutter doctor`
Expected: "Flutter" and "Android toolchain" lines show a green check (✓). If "Android toolchain" is not OK, run `flutter doctor --android-licenses` and accept, and/or `flutter config --android-sdk <path>` / `flutter config --jdk-dir <path>` to point at your existing SDK/JDK. The "Connected device" line may be empty — that is fine; the scaffold and all tests run on the host.

- [ ] **Confirm the working directory is the repo root**

Run: `git status`
Expected: on branch `master`, working tree clean, and the repo contains `opds_browser_spec.md` and `docs/`. All subsequent commands run from this directory.

---

## Task 1: Generate the Android-only Flutter project

`flutter create` scaffolds project files alongside the existing `opds_browser_spec.md` and `docs/` without clobbering them. `--org monster.greyde` makes the `applicationId` resolve to `monster.greyde.opds_browser`.

**Files:**
- Create (generated): `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `.metadata`, `lib/main.dart`, `test/widget_test.dart`, `android/` tree
- Test: `test/widget_test.dart` (template-generated, used only to confirm the toolchain)

- [ ] **Step 1: Generate the project**

Run:
```bash
flutter create --org monster.greyde --project-name opds_browser --platforms android .
```
Expected: output ends with "All done!" and lists created files. No `ios/`, `web/`, `linux/`, `macos/`, or `windows/` directories are created.

- [ ] **Step 2: Resolve dependencies**

Run: `flutter pub get`
Expected: "Got dependencies!" (or "Changed N dependencies!"), exit 0.

- [ ] **Step 3: Run the template test to confirm the toolchain works**

Run: `flutter test`
Expected: PASS — "All tests passed!" (the generated counter widget test).

- [ ] **Step 4: Confirm analyzer is clean on the template**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Scaffold Android-only Flutter project (flutter create)"
```

---

## Task 2: Replace the template app with the placeholder app + smoke test (TDD)

Replace the generated counter app with `OpdsBrowserApp` (in its own `app.dart`) and a smoke test that pumps it. Write the test first; it fails because `app.dart` does not exist yet.

**Files:**
- Create: `lib/app.dart`
- Modify (replace contents): `lib/main.dart`
- Create: `test/smoke_test.dart`
- Delete: `test/widget_test.dart`

- [ ] **Step 1: Write the failing smoke test**

Create `test/smoke_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/app.dart';

void main() {
  testWidgets('App renders the placeholder home', (tester) async {
    await tester.pumpWidget(const OpdsBrowserApp());
    expect(find.text('OPDS Browser'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Delete the template test so it does not break compilation**

The generated `test/widget_test.dart` imports `package:opds_browser/main.dart` and references `MyApp`, which we are about to remove.

Run: `git rm test/widget_test.dart`
Expected: `rm 'test/widget_test.dart'`.

- [ ] **Step 3: Run the smoke test to verify it fails**

Run: `flutter test test/smoke_test.dart`
Expected: FAIL — compile error, `Target of URI doesn't exist: 'package:opds_browser/app.dart'` (or "OpdsBrowserApp isn't defined").

- [ ] **Step 4: Create the placeholder app**

Create `lib/app.dart`:
```dart
import 'package:flutter/material.dart';

/// Root application widget. A minimal placeholder for the scaffold step;
/// theming, Riverpod, and go_router are wired up in later steps.
class OpdsBrowserApp extends StatelessWidget {
  const OpdsBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OPDS Browser',
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
      home: const Scaffold(
        body: Center(child: Text('OPDS Browser')),
      ),
    );
  }
}
```

- [ ] **Step 5: Replace `main.dart` to use the new app**

Replace the entire contents of `lib/main.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:opds_browser/app.dart';

void main() => runApp(const OpdsBrowserApp());
```

- [ ] **Step 6: Run the smoke test to verify it passes**

Run: `flutter test test/smoke_test.dart`
Expected: PASS — "All tests passed!"

- [ ] **Step 7: Confirm analyzer is still clean**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Replace template app with OpdsBrowserApp placeholder + smoke test"
```

---

## Task 3: Create the source/test directory layout

Establish the `domain` / `data` / `ui` boundaries and `test/fixtures` now so later steps drop files into a known structure. Empty directories need a tracked placeholder to exist in git.

**Files:**
- Create: `lib/domain/.gitkeep`, `lib/data/.gitkeep`, `lib/ui/.gitkeep`, `test/fixtures/.gitkeep`, `test/domain/.gitkeep`, `test/data/.gitkeep`, `test/ui/.gitkeep`

- [ ] **Step 1: Create the directories with placeholders**

Run:
```bash
mkdir -p lib/domain lib/data lib/ui test/fixtures test/domain test/data test/ui
```
Then create an empty file named `.gitkeep` in each of: `lib/domain`, `lib/data`, `lib/ui`, `test/fixtures`, `test/domain`, `test/data`, `test/ui`.

- [ ] **Step 2: Verify the layout**

Run: `git status --porcelain`
Expected: seven new `.gitkeep` paths listed under the directories above.

- [ ] **Step 3: Confirm nothing broke**

Run: `flutter analyze`
Expected: "No issues found!" (empty dirs and `.gitkeep` files are ignored by the analyzer).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add domain/data/ui and test directory layout"
```

---

## Task 4: Declare all dependencies up front

Add every §2 production package and the host-test dev dependency. `flutter pub add` resolves the latest compatible versions and writes caret constraints into `pubspec.yaml` automatically — do not hand-pin versions.

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`

- [ ] **Step 1: Add production dependencies**

Run:
```bash
flutter pub add flutter_riverpod go_router http xml sqflite shared_preferences cached_network_image open_filex shared_storage path
```
Expected: each package resolves and is added; exit 0.

If `shared_storage` fails to resolve against the current Flutter/Dart SDK or is flagged discontinued, substitute an equivalent maintained SAF/MediaStore plugin (the requirement is behavioral per parent spec §10) and note the substitution in the commit message. Do not block the scaffold on this.

- [ ] **Step 2: Add the host-test dev dependency**

Run: `flutter pub add dev:sqflite_common_ffi`
Expected: added under `dev_dependencies`; exit 0.

- [ ] **Step 3: Resolve and confirm the lockfile updated**

Run: `flutter pub get`
Expected: "Got dependencies!"; `pubspec.lock` now lists the new packages.

- [ ] **Step 4: Confirm analyzer and tests still pass (no deps are imported yet)**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" then "All tests passed!". Declared-but-unused dependencies do not produce analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Declare all production and test dependencies"
```

---

## Task 5: Enable strict analyzer modes

Parent spec §2 mandates `strict-casts`, `strict-raw-types`, and `strict-inference`. The generated `analysis_options.yaml` already includes `flutter_lints`; add the strict language block.

**Files:**
- Modify: `analysis_options.yaml`

- [ ] **Step 1: Replace `analysis_options.yaml` contents**

Replace the entire file with:
```yaml
# Static analysis configuration. See https://dart.dev/lints.
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
    strict-inference: true
```

- [ ] **Step 2: Verify the analyzer is clean under strict modes**

Run: `flutter analyze`
Expected: "No issues found!" (the minimal `app.dart`/`main.dart` have no implicit casts, raw types, or uninferred types).

- [ ] **Step 3: Verify tests still pass**

Run: `flutter test`
Expected: "All tests passed!"

- [ ] **Step 4: Commit**

```bash
git add analysis_options.yaml
git commit -m "Enable strict analyzer modes (casts, raw-types, inference)"
```

---

## Task 6: Configure Android (minSdk, app label, verify applicationId)

Set `minSdkVersion 29` (parent spec §10.1) and the user-facing app label. The `applicationId` was already set to `monster.greyde.opds_browser` by `--org` in Task 1 — this task verifies it.

**Files:**
- Modify: `android/app/build.gradle.kts` (Kotlin DSL; recent Flutter) **or** `android/app/build.gradle` (Groovy; older Flutter)
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Locate the Gradle build file and confirm the applicationId**

Run: `grep -R "applicationId" android/app/`
Expected: a line `applicationId = "monster.greyde.opds_browser"` (Kotlin DSL) or `applicationId "monster.greyde.opds_browser"` (Groovy). If it differs, the `--org` was wrong in Task 1 — fix the value here to `monster.greyde.opds_browser`.

- [ ] **Step 2: Set `minSdk` to 29**

In the Gradle build file from Step 1, inside the `defaultConfig { ... }` block, find the `minSdk` line (it reads `minSdk = flutter.minSdkVersion` in Kotlin DSL, or `minSdkVersion flutter.minSdkVersion` in Groovy) and change it to the literal `29`:
- Kotlin DSL: `minSdk = 29`
- Groovy: `minSdkVersion 29`

- [ ] **Step 3: Set the app display label**

In `android/app/src/main/AndroidManifest.xml`, find the `<application` tag's `android:label` attribute (generated as `android:label="opds_browser"`) and change it to:
```xml
android:label="OPDS Browser"
```

- [ ] **Step 4: Verify the Dart toolchain is unaffected**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" then "All tests passed!". (A full Android build is not run here; it is exercised when the app is first launched on a device in a later step.)

- [ ] **Step 5: Commit**

```bash
git add android/
git commit -m "Configure Android: minSdk 29 and 'OPDS Browser' label"
```

---

## Task 7: Add the cross-platform check runner and Makefile

`tool/check.dart` is the primary, OS-independent gate; the `Makefile` is a thin convenience wrapper. `make check` and `dart run tool/check.dart` must both run analyze then test, exiting non-zero on any failure.

**Files:**
- Create: `tool/check.dart`
- Create: `Makefile`

- [ ] **Step 1: Create the check runner**

Create `tool/check.dart`:
```dart
import 'dart:io';

/// Runs `flutter <args>`, streaming output to this process's stdio.
/// Returns the child's exit code.
Future<int> _runFlutter(String label, List<String> args) async {
  stdout.writeln('\n=== $label: flutter ${args.join(' ')} ===');
  final process = await Process.start(
    'flutter',
    args,
    runInShell: true, // resolves flutter.bat on Windows
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

Future<void> main() async {
  final analyzeCode = await _runFlutter('analyze', ['analyze']);
  if (analyzeCode != 0) {
    stderr.writeln('\nflutter analyze failed.');
    exit(analyzeCode);
  }

  final testCode = await _runFlutter('test', ['test']);
  if (testCode != 0) {
    stderr.writeln('\nflutter test failed.');
    exit(testCode);
  }

  stdout.writeln('\nAll checks passed.');
}
```

- [ ] **Step 2: Create the Makefile**

Create `Makefile` (indentation MUST be tabs, not spaces):
```makefile
.PHONY: get format analyze test check

get:
	flutter pub get

format:
	dart format .

analyze:
	flutter analyze

test:
	flutter test

check:
	dart run tool/check.dart
```

- [ ] **Step 3: Run the check runner directly**

Run: `dart run tool/check.dart`
Expected: prints the analyze and test sections, then "All checks passed.", exit 0.

- [ ] **Step 4: Run the Makefile wrapper (if `make` is available)**

Run: `make check`
Expected: same output as Step 3, exit 0. (On a Windows shell without `make`, skip this step — `dart run tool/check.dart` is the canonical entry point.)

- [ ] **Step 5: Commit**

```bash
git add tool/check.dart Makefile
git commit -m "Add tool/check.dart runner and Makefile (make check)"
```

---

## Definition of done (verify before declaring the scaffold complete)

- [ ] `flutter doctor` reports Flutter + Android toolchain OK.
- [ ] `dart run tool/check.dart` exits 0 with "No issues found!" (analyze) and "All tests passed!" (test).
- [ ] `git status` is clean; the directory layout from the spec §5 is committed.
- [ ] `pubspec.lock` is committed and lists all §2 dependencies.

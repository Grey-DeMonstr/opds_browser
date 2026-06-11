# Step 1 — Project Scaffold: Design Spec

**Date:** 2026-06-11
**Parent spec:** [`opds_browser_spec.md`](../../../opds_browser_spec.md) — implements §14 step 1 ("Project scaffold, lints, Makefile, CI-style `make check`").
**Status:** Approved for planning.

---

## 1. Goal

Produce a Flutter project skeleton that **compiles, analyzes clean under strict lints, and has a green check command** — a known-good baseline every later step starts from. No business logic, no domain models, no networking. The scaffold is "done" when the check command (analyze + test) passes.

This spec covers only step 1 of the parent spec's implementation order. Steps 2+ (domain models, `Opds1Client`, DB, screens, downloads) are explicitly out of scope here.

## 2. Development environment (decided)

- **Develop natively on Windows.** The Android SDK and JDK are already installed on the Windows host; the repo already lives on `E:\dev\opds_browser`. Native Windows development avoids the WSL2↔`/mnt/e` filesystem performance penalty and gives smooth emulator/device access.
- **Claude Code** should be run on Windows (native terminal or the VS Code extension) for the implementation steps so the toolchain commands run against the real Flutter install. The repo files are identical from either side.
- **Check runner is cross-platform Dart.** Primary entry point is `dart run tool/check.dart` (works on Windows, WSL, and CI with zero extra installs). A thin `Makefile` wraps it for convenience but is optional and not required on Windows.

## 3. Software to install (Windows host)

1. **Flutter SDK (latest stable)** — bundles Dart. Add `flutter\bin` to `PATH`. This is the only major new install.
2. **Reuse existing Android SDK + JDK.** Verify Flutter finds them via `flutter doctor`; if not, set `flutter config --android-sdk <path>` and/or `flutter config --jdk-dir <path>`. Accept licenses once with `flutter doctor --android-licenses`.
3. **Git for Windows** — if running tooling from a Windows shell (the repo is already a git repo).
4. *(Optional)* **VS Code with the Flutter + Dart extensions**, or **Android Studio**, for editing and the AVD manager.
5. *(Optional, only to run the app)* **An Android emulator (AVD) or a physical device.** Not needed for the scaffold or for any of the host-run tests (§13 of the parent spec runs everything via `flutter test`).

`flutter doctor` should report Flutter + Android toolchain OK before scaffolding. `make` / GNU Make is **not** required (the Dart check script is primary).

## 4. Approach (decided)

**Lean scaffold, declare all dependencies up front.** Create the Flutter project (Android-only), restructure into `domain/data/ui`, declare *all* parent-spec §2 packages in `pubspec.yaml` now, enable strict lints, add the check runner, and ship one trivial smoke test so the test command is green. Declaring dependencies now locks the lockfile and surfaces version conflicts on day one; `main.dart` stays a minimal placeholder so nothing is wired up yet (declared-but-unused deps do not fail `flutter analyze`).

Rejected alternatives:
- *Minimal deps, add per step* — defers dependency-resolution conflicts and forces re-touching `pubspec.yaml` every step.
- *Scaffold + first vertical slice* — bleeds step 2 (`OpdsClient`/`ParsedFeed`) into step 1; scope creep against the agreed order.

## 5. Directory layout

Matches parent spec §2. Empty directories get a placeholder so they exist in git and are importable:

```
lib/
  domain/        # placeholder (.gitkeep); populated step 2+
  data/          # placeholder (.gitkeep)
  ui/            # placeholder (.gitkeep)
  app.dart       # MaterialApp + light/dark theme; temporary placeholder home
  main.dart      # void main() => runApp(const OpdsBrowserApp());
test/
  fixtures/      # placeholder (.gitkeep); populated step 2+
  smoke_test.dart  # pumps the app, asserts it renders
tool/
  check.dart     # runs `flutter analyze` then `flutter test`, non-zero exit on failure
docs/
  superpowers/specs/2026-06-11-project-scaffold-design.md   # this file
Makefile         # convenience wrapper around tool/check.dart
analysis_options.yaml
pubspec.yaml
```

Riverpod and `go_router` wiring are deferred to step 6 ("navigation shell"). For step 1, `app.dart` is a plain `MaterialApp` with a placeholder `Scaffold` (e.g. centered "OPDS Browser" text). The smoke test pumps `OpdsBrowserApp` and asserts that text renders.

## 6. `pubspec.yaml`

- **dependencies:** `flutter_riverpod`, `go_router`, `http`, `xml`, `sqflite`, `shared_preferences`, `cached_network_image`, `open_filex`, `shared_storage`, `path`.
- **dev_dependencies:** `flutter_lints`, `flutter_test` (SDK), `sqflite_common_ffi`.
- Versions: use latest stable compatible constraints (caret ranges) resolved at scaffold time; commit `pubspec.lock`.

`shared_storage` is the SAF/MediaStore plugin named in parent spec §2; if it proves unmaintained at scaffold time, substitute an equivalent maintained SAF/MediaStore plugin (the requirement is behavioral, per §10) and note the substitution.

## 7. `analysis_options.yaml`

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
    strict-inference: true
```

Strict modes are mandated by parent spec §2. Keep the lint set at `flutter_lints` defaults for now; project-specific rule tuning can come later if noise appears.

## 8. Android configuration

- `minSdkVersion 29` — per parent spec §10.1, avoids legacy storage permissions entirely.
- `compileSdkVersion` / `targetSdkVersion` — latest stable.
- `applicationId`: `monster.greyde.opds_browser`.
- App label: "OPDS Browser" (placeholder per parent spec §15.2).
- Android-only: do not add iOS/web/desktop platform folders beyond what `flutter create` generates; no platform conditional branches (parent spec §1.2).

## 9. `tool/check.dart` and `Makefile`

`tool/check.dart`: a small Dart program that runs `flutter analyze`, then (if clean) `flutter test`, streaming output and exiting non-zero if either fails. Cross-platform (no shell-specific syntax).

`Makefile` targets (thin wrappers; `check` is the gate):
- `get` → `flutter pub get`
- `format` → `dart format .`
- `analyze` → `flutter analyze`
- `test` → `flutter test`
- `check` → `dart run tool/check.dart`

## 10. Definition of done

1. `flutter doctor` reports Flutter + Android toolchain OK on the Windows host.
2. `flutter pub get` resolves with no conflicts; `pubspec.lock` committed.
3. `dart run tool/check.dart` (and equivalently `make check`) exits 0:
   - `flutter analyze` reports **zero** issues under the strict `analysis_options.yaml`.
   - `flutter test` runs the smoke test **green**.
4. Directory layout from §5 is in place and committed.

## 11. Out of scope (deferred to later steps)

- Any domain model, `OpdsClient` interface, or parsing (`step 2`).
- DB layer, repositories, caching (`steps 4–5`).
- Any real screen, Riverpod providers, or `go_router` routes (`steps 6+`).
- A separate CI YAML — `dart run tool/check.dart` *is* the CI-style gate; wiring it into a hosted CI provider is a later, optional concern.
- App icon and final display name (parent spec §15.2).

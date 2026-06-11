# OPDS Browser

Android-only Flutter app for browsing OPDS catalogues and downloading books.
Single package, no monorepo. **Android only — no iOS, no iOS-specific code.**

## Environment

**Development is Windows-native.** Use `PowerShell` for all shell commands — not `Bash`.

The `Bash` tool calls Cygwin bash, which inherits Windows paths. Cygwin cannot resolve
`flutter.bat` through Windows `PATH`, so `flutter`, `dart`, `git`, and `make` calls
from `Bash` fail silently or with confusing errors. Always use `PowerShell` instead.

## Commands

```powershell
flutter pub get               # resolve dependencies
flutter analyze               # static analysis (must be clean)
flutter test                  # run all tests (host only, no device needed)
dart run tool/check.dart      # canonical quality gate: analyze + test
make check                    # same, via Makefile
```

> `tool/check.dart` and `Makefile` are created in scaffold Task 7.

## Architecture

```
lib/
  domain/    # entities, value objects, repository interfaces, OpdsClient interface
  data/      # OPDS 1.x impl, sqflite DAOs, settings store, download engine
  ui/        # screens, widgets, Riverpod providers
  app.dart   # router + theme (MaterialApp, go_router wired here eventually)
  main.dart  # runApp entry point
test/
  fixtures/  # .xml OPDS feed fixtures committed to the repo
  domain/    # unit tests for domain layer
  data/      # unit tests for data layer (sqflite via sqflite_common_ffi on host)
  ui/        # widget tests (Riverpod overrides with fakes — no real network/DB)
```

## Tech Stack (decided — do not substitute)

| Concern | Package |
|---------|---------|
| State | `flutter_riverpod` — plain `Notifier`/`AsyncNotifier`, no codegen |
| Navigation | `go_router` |
| HTTP | `http` (not dio) |
| XML | `xml` |
| Local DB | `sqflite` (raw SQL, thin DAOs) |
| Settings | `shared_preferences` |
| Cover images | `cached_network_image` |
| Open file | `open_filex` |
| Android storage | `shared_storage` (SAF + MediaStore) |
| Lints | `flutter_lints` + strict modes (see `analysis_options.yaml`) |

## Key Constraints

- **TDD is mandatory.** Write the failing test first, then implement.
- **`flutter test` only** — all tests run on the host. No `integration_test`, no emulator, no device.
- **Pure Dart in `domain/` and `data/`.** No Flutter bindings; these layers must be testable without a Flutter environment.
- **`flutter analyze` must be clean** and **`flutter test` must pass** before any task is considered complete.
- **Android minSdk >= 29** (MediaStore API; no legacy storage permissions needed). Can be raised if needed.
- `applicationId` / `namespace`: `monster.greyde.opds_browser`
- Strict analyzer modes: `strict-casts`, `strict-raw-types`, `strict-inference` (Task 5 of scaffold plan).

## Project spec

Full spec: `docs/opds_browser_spec.md`

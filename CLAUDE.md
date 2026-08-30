# OPDS Browser

Android-only Flutter app for browsing OPDS catalogues and downloading books.
Single package, no monorepo. **Android only — no iOS, no iOS-specific code.**

## Environment

**Development is Windows-native.** Use `PowerShell` for all shell commands — not `Bash`.

The `Bash` tool calls Cygwin bash, which inherits Windows paths. Cygwin cannot resolve
`flutter.bat` through Windows `PATH`, so `flutter`, `dart`, `git`, and `make` calls
from `Bash` fail silently or with confusing errors. Always use `PowerShell` instead.

# Repository

All development happens directly on `master` — no feature branches, no PRs.
`origin` is `git@github.com:Grey-DeMonstr/opds_browser.git` and `master` is
pushed to it: GitHub Actions verifies every push, and pushing a `vX.Y.Z` tag
cuts a release. See
`docs/superpowers/specs/2026-08-22-android-release-pipeline-design.md`.

## Commands

```powershell
flutter pub get               # resolve dependencies
dart format .                 # format all Dart files
flutter analyze               # static analysis (must be clean)
flutter test                  # run all tests (host only, no device needed)
dart run tool/check_privacy.dart  # scan tracked files for private data
dart run tool/check.dart      # canonical quality gate: analyze + test
make check                    # same, via Makefile
```

`tool/check_privacy.dart` rejects any hostname, IP address or absolute
filesystem path that is not on the allow-list it carries. The list is an
*allow*-list on purpose: a deny-list would have to name the very strings we
keep out of the repository. When a genuinely public host or a synthetic test
path trips it, add it to `allowedHosts` / `allowedPaths` there. Prefer the
RFC 2606 reserved names (`example.com`, `*.test`, `*.invalid`) and the RFC 5737
documentation addresses (`192.0.2.x`) in new tests — those pass without any
allow-list entry.

The sweep over the working tree runs as an ordinary test in
`test/tool/check_privacy_test.dart`, so `flutter test` covers it. **It is
local-only**: that test is skipped when `CI` is set, because catching private
data is a pre-commit concern. The rules themselves are unit-tested and do run
on CI.

## Architecture

```
lib/
  domain/    # entities, value objects, repository interfaces, OpdsClient interface
  data/      # OPDS 1.x impl, sqflite DAOs, settings store, download engine
    opds1/   # Opds1Client + feed parser
  ui/        # screens, widgets, Riverpod providers
  app.dart   # router + theme (MaterialApp, go_router wired here eventually)
  main.dart  # runApp entry point
test/
  fixtures/  # .xml OPDS feed fixtures committed to the repo
  domain/    # unit tests for domain layer
  data/      # unit tests for data layer (sqflite via sqflite_common_ffi on host)
  ui/        # widget tests (Riverpod overrides with fakes — no real network/DB)
  tool/      # unit tests for scripts in tool/ (imported by relative path)
```

## Tech Stack (decided — do not substitute)

| Concern | Package |
|---------|---------|
| State | `flutter_riverpod` — plain `Notifier`/`AsyncNotifier`, no codegen |
| Navigation | `go_router` |
| HTTP | `http` (not dio) |
| XML | `xml` |
| Entry descriptions | `html` — feeds ship markup `xml` cannot parse (bare `<br>`, stray FB2 tags) |
| Local DB | `sqflite` (raw SQL, thin DAOs) |
| Settings | `shared_preferences` |
| Cover images | `cached_network_image` |
| Android storage | `saf_stream` + `saf_util` (SAF only — a custom folder is always required) |
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

Two documents, both describing the app as built:

- `docs/functional_spec.md` — what the app does. No code.
- `docs/technical_spec.md` — how it is built. All code examples live here.

The pre-implementation v1 spec is archived at
`docs/archive/2026-06-11-opds_browser_spec-v1.md` and is largely out of date — do
not treat it as current.

All noticeable features should be added to these specs before implementation to keep them
consistent.

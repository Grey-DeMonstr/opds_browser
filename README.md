# OPDS Browser

An Android app for browsing open OPDS catalogues and downloading books.

No accounts, no login, no DRM. Downloaded books open in whichever reader app you already have installed.

## Features

- Add any number of OPDS 1.x catalogues by URL
- Browse folder hierarchies with instant back-navigation (persistent cache)
- Download a single book — prefers FB2, falls back to EPUB/PDF/MOBI
- Download an entire folder recursively (with cycle protection and safety limits)
- Bookmark favourite folders for one-tap access from the home screen
- Save to the system Downloads folder (Windows only) or pick a custom folder via SAF
- Optionally organise files into per-author and per-series subfolders

## Requirements

- Android 10+ (API 29)
- An installed ebook reader (Moonreader, KOReader, LxReader, etc.) to open downloaded files

## Building

Requires [Flutter](https://docs.flutter.dev/get-started/install) (latest stable).

```powershell
flutter pub get
flutter build apk
```

Run on a connected device or emulator:

```powershell
flutter run
```

## Development

```powershell
flutter pub get          # resolve dependencies
flutter analyze          # static analysis
flutter test             # unit and widget tests (no device needed)
dart run tool/check.dart # canonical quality gate: analyze + test
```

### Architecture

```
lib/
  domain/   # entities, repository interfaces, OpdsClient interface
  data/     # OPDS 1.x parser, sqflite DAOs, download engine, settings
  ui/       # screens, widgets, Riverpod providers
test/
  fixtures/ # real-world OPDS XML samples used in unit tests
  domain/   # pure-Dart unit tests
  data/     # DB tests via sqflite_common_ffi (no emulator)
  ui/       # widget tests with Riverpod provider overrides
```

Business logic lives in plain Dart with no Flutter dependency so it is fully testable on the host without a device.

### Tech stack

| Concern | Package |
|---------|---------|
| State | `flutter_riverpod` |
| Navigation | `go_router` |
| HTTP | `http` |
| XML | `xml` |
| Local DB | `sqflite` |
| Settings | `shared_preferences` |
| Cover images | `cached_network_image` |
| Open file | `open_filex` |
| Storage (SAF) | `saf_stream`, `saf_util` |

## License

GPL v3 — see [LICENSE](LICENSE).

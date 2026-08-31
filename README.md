# OPDS Browser

An Android app for browsing open OPDS catalogues and downloading books.

No accounts, no login, no DRM. Downloaded books open in whichever reader app you
already have installed.

## Features

- Add any number of OPDS 1.x catalogues by URL
- Browse folder hierarchies with instant back-navigation (folders are cached)
- Search a whole catalogue, where the catalogue offers a search
- Download a single book — prefers FB2, falls back to EPUB, PDF or MOBI
- Download a whole folder tree, picking what to keep, with cycle protection and
  safety limits
- Bookmark favourite folders for one-tap access from the home screen
- File downloads into per-author and per-series subfolders, or turn that off
- Tidy up the downloaded FB2 library against those folder names *(in development)*

Downloads go to one folder you choose the first time the app needs one.

## Where to get it

- **Google Play** — signed by Google under Play App Signing.
- **GitHub Releases** — a universal APK signed with the project's own upload key.

**The two are not interchangeable.** Android refuses to install an app over a copy
signed with a different key, so you cannot upgrade from the Play build to the APK
build or back again. Switching channels means uninstalling first, which deletes
the app's settings and catalogue cache. Downloaded books are unaffected — they
live in the folder you chose, not in the app's private storage.

## Requirements

- Android 10+ (API 29)
- An installed ebook reader (Moon+ Reader, KOReader, LxReader, …) to open
  downloaded files

## Building

Requires [Flutter](https://docs.flutter.dev/get-started/install) (latest stable).

```powershell
flutter pub get
flutter build apk
```

## Development

```powershell
flutter analyze          # static analysis
flutter test             # unit and widget tests (no device needed)
dart run tool/check.dart # canonical quality gate: analyze + test
```

Everything is tested on the host — no emulator, no device. There is also a Windows
build (`flutter run -d windows`) used for working on screens with hot reload; only
Android is released.

```
lib/
  domain/   # entities, repository interfaces, OpdsClient interface, pure rules
  data/     # OPDS 1.x parser, sqflite DAOs, download engine, storage, settings
  ui/       # screens, widgets, Riverpod providers
test/
  fixtures/ # real-world OPDS XML samples
  domain/   # pure-Dart unit tests
  data/     # DB tests via sqflite_common_ffi
  ui/       # widget tests with Riverpod provider overrides
```

Business logic lives in plain Dart with no Flutter dependency, so it is fully
testable on the host.

| Concern | Package |
|---------|---------|
| State | `flutter_riverpod` |
| Navigation | `go_router` |
| HTTP | `http` |
| Feed XML / descriptions | `xml`, `html` |
| Local DB | `sqflite` |
| Settings | `shared_preferences` |
| Cover images | `cached_network_image` |
| Storage (SAF) | `saf_stream`, `saf_util` |

Design and behaviour are specified in [docs/functional_spec.md](docs/functional_spec.md)
(what the app does) and [docs/technical_spec.md](docs/technical_spec.md) (how it is
built).

## License

GPL v3 — see [LICENSE](LICENSE). Privacy policy: [PRIVACY.md](PRIVACY.md).

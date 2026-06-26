# Inferred Series from Browse URL

**Date:** 2026-06-26

## Problem

Some OPDS catalogues (e.g. Flibusta) embed the series name directly in the browse page URL as a `series` query parameter (e.g. `?series=The+Wheel+of+Time`), but individual book entries within that page carry no `series` metadata. When `createSeriesFolder` is enabled in settings, these books are saved flat rather than into a series subfolder, which defeats the folder-organisation feature.

## Goal

1. Infer the series from the URL when `entry.series` is null.
2. Use the inferred series for download folder/filename construction (single-book downloads only — folder download already has its own context).
3. Display the inferred series in the book list's series label in italics for debugging visibility.

## Approach

Explicit parameter threading (approach A). The inferred series is navigation context, not book metadata, so it never touches `BookEntry` and flows as an optional `String?` parameter through the call chain.

## Components

### 1. `inferSeriesFromUrl(Uri url)` — `lib/domain/download_utils.dart`

```dart
String? inferSeriesFromUrl(Uri url) {
  final value = url.queryParameters['series'];
  return (value != null && value.isNotEmpty) ? value : null;
}
```

Pure function, no dependencies. Returns the decoded series name or null.

Edge cases handled:
- Missing `series` param → null
- Empty string value → null
- Percent-encoded characters → decoded automatically by `Uri.queryParameters`

### 2. `buildPathSegments` and `buildFileName` — `lib/domain/download_utils.dart`

Both gain a `String? inferredSeries` parameter. Wherever `entry.series` is used, replace with `entry.series ?? inferredSeries`. No other logic changes.

### 3. `BookDownloader.download()` — `lib/data/book_downloader.dart`

Gains `String? inferredSeries` parameter, forwards it to `buildPathSegments` and `buildFileName`.

### 4. `DownloadNotifier.start()` — `lib/ui/providers.dart`

Gains `String? inferredSeries` parameter. Forwards to:
- `buildFileName(...)` (for the snackbar result filename)
- `downloader.download(...)` (for actual storage)

### 5. `_BrowseContent.build()` — `lib/ui/browse_screen.dart`

Computes once:
```dart
final inferredSeries = inferSeriesFromUrl(url);
```

Passes `inferredSeries` to each `_BookEntryTile` constructor.

### 6. `_BookEntryTile` — `lib/ui/browse_screen.dart`

New constructor param: `final String? inferredSeries`.

Display logic:
- Resolve: `final effectiveSeries = entry.series ?? inferredSeries;`
- If `effectiveSeries` is null → empty text (current behaviour)
- Format `seriesText` from `effectiveSeries` and `entry.seriesIndex` (same pattern as today)
- Style: italic when `entry.series == null && inferredSeries != null`, normal otherwise

`seriesIndex` is never inferred — it remains null for inferred series, so the label shows just the series name without `#N`.

`_onDownloadTap()` passes `widget.inferredSeries` to `notifier.start()`.

## Data Flow

```
widget.url
  └─ inferSeriesFromUrl()
       └─ inferredSeries: String?
            ├─ _BookEntryTile (display, italic)
            └─ DownloadNotifier.start(inferredSeries)
                 └─ BookDownloader.download(inferredSeries)
                      ├─ buildPathSegments(settings, entry, inferredSeries)
                      └─ buildFileName(entry, link, settings, inferredSeries)
```

## Testing

| Layer | What to test |
|---|---|
| `inferSeriesFromUrl` | URLs with `series` param, without, empty value, encoded chars |
| `buildPathSegments` | inferred series used when `entry.series` null + `createSeriesFolder` true; real series takes precedence |
| `buildFileName` | inferred series in filename prefix when `entry.series` null + `createSeriesFolder` false |
| `DownloadNotifier` | `start()` passes inferred series through to downloader |
| `_BookEntryTile` widget | italic style when inferred; normal style when from metadata; no label when both null |

## Out of Scope

- Folder download (`FolderDownloadJob`) — it crawls the catalogue recursively and has its own URL context per page; this feature is not applied there.
- Persisting or caching the inferred series — it is derived fresh from the URL on each build.
- `seriesIndex` inference — not attempted; only the series name is inferred.

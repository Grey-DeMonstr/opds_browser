# Opds1Client — Design Spec

**Date:** 2026-06-12
**Step:** 3 of 11 (spec §14)
**Status:** Approved

---

## Goal

Implement `Opds1Client`, the concrete OPDS 1.x protocol implementation that satisfies the `OpdsClient` domain interface. The implementation is split into three collaborating units to allow the HTTP transport to be reused when OPDS 2 support is added later — without modifying any existing code.

---

## File Structure

```
lib/data/
  opds_feed_parser.dart          # abstract interface OpdsFeedParser
  opds_http_fetcher.dart         # OpdsHttpFetcher — HTTP transport only
  opds1/
    opds1_feed_parser.dart       # Opds1FeedParser implements OpdsFeedParser
    opds1_client.dart            # Opds1Client implements OpdsClient

test/data/
  opds1_feed_parser_test.dart    # fixture-based parser tests (no HTTP mocking)
  opds1_client_test.dart         # client tests (MockClient)
```

When OPDS 2.0 is added: `opds2/opds2_feed_parser.dart` + `opds2/opds2_client.dart` are created. `OpdsFeedParser`, `OpdsHttpFetcher` are untouched.

---

## Unit 1: `OpdsFeedParser` interface (`lib/data/opds_feed_parser.dart`)

```dart
import 'package:opds_browser/domain/models.dart';

abstract interface class OpdsFeedParser {
  ParsedFeed parse(List<int> bytes, Uri feedUrl);
}
```

`feedUrl` is passed through from the HTTP layer so the parser can resolve relative hrefs when `xml:base` is absent from the feed.

---

## Unit 2: `OpdsHttpFetcher` (`lib/data/opds_http_fetcher.dart`)

Constructor-injectable `http.Client` (enables `MockClient` in tests).

Responsibilities:
- Sets `User-Agent: OpdsBrowser/1.0` on every request.
- Applies a 20 s timeout via `Future.timeout`.
- Redirects are followed automatically by `http.IOClient` (default limit: 5), satisfying the spec requirement without manual implementation.
- Reads the response body as raw bytes (`List<int>`).
- Throws `NetworkException` on connection/timeout errors.
- Throws `HttpStatusException(statusCode, ...)` on any non-2xx response.
- Returns raw bytes — no encoding conversion. That is the parser's responsibility because only the XML prolog declares the encoding.

```dart
class OpdsHttpFetcher {
  final http.Client _client;
  OpdsHttpFetcher(this._client);

  Future<List<int>> fetch(Uri url) async { ... }
}
```

---

## Unit 3: `Opds1FeedParser` (`lib/data/opds1/opds1_feed_parser.dart`)

Implements `OpdsFeedParser`. All parsing logic lives here. No I/O — pure bytes-in, `ParsedFeed`-out.

### Encoding detection (`decodeXmlBytes`)

1. Peek at the first 200 bytes decoded as latin1 (ASCII-safe) to extract the `encoding="..."` value from the XML prolog.
2. If UTF-8 or absent: `utf8.decode(bytes, allowMalformed: false)`.
3. If windows-1251: decode using a 128-entry `const List<int>` lookup table mapping bytes `0x80–0xFF` to their Unicode code points. Pure Dart — no new dependencies, works in host tests.
4. Pass the resulting `String` to `XmlDocument.parse()`. Any `XmlException` is wrapped into `ParseException`.

### URL resolution

Pure function `Uri resolveHref(String href, Uri base)`:
- The parser reads `xml:base` from the `<feed>` element first; if absent, uses `feedUrl`.
- Every link `href` is resolved against this base via `base.resolve(href)`.

### Entry classification

Applied to each `<entry>` element in feed order:

1. Collect all `<link>` child elements.
2. If any link's `rel` **starts with** `http://opds-spec.org/acquisition` → classify as `BookEntry`.
3. Else if any link's `type` **contains** `application/atom+xml` → classify as `NavigationEntry`.
4. Neither → silently drop.

### `BookEntry` field extraction

| Field | Source |
|---|---|
| `title` | `<title>` |
| `authors` | All `<author><name>` values, document order |
| `series`, `seriesIndex` | `extractSeries(entry)` — see below |
| `summary` | `<summary>` text, HTML-stripped via `stripHtml()` |
| `coverUrl` | Prefer `rel="http://opds-spec.org/image/thumbnail"`, fall back to `rel="http://opds-spec.org/image"`; null if neither |
| `acquisitionLinks` | All links with qualifying `rel`; `mimeToLabel(type)` applied |

### `NavigationEntry` field extraction

| Field | Source |
|---|---|
| `title` | `<title>` |
| `subtitle` | First non-empty `<content>` or `<summary>` text; null if neither |
| `url` | Resolved href of the qualifying `application/atom+xml` link |

### Pure functions (all top-level in `opds1_feed_parser.dart`, all unit-tested)

**`mimeToLabel(String mimeType) → String`**

| MIME type | Label |
|---|---|
| `application/fb2`, `application/x-fictionbook+xml` | `FB2` |
| `application/fb2+zip`, `application/x-zip-compressed-fb2` | `FB2.ZIP` |
| `application/epub+zip` | `EPUB` |
| `application/pdf` | `PDF` |
| `application/x-mobipocket-ebook` | `MOBI` |
| anything else | uppercase subtype (e.g. `application/djvu` → `DJVU`) |

**`extractSeries(XmlElement entry) → ({String? series, double? seriesIndex})`**

Checks in order, first match wins:
1. Calibre namespace: `<calibre:series>` (text) + `<calibre:series_index>` (parsed as double).
2. DC Terms: `<dcterms:isPartOf>` (text) → series name; no index available from this element.
3. `opds:series` or `schema:Series` link/element variants if present.
4. Returns `(series: null, seriesIndex: null)` if none found.

**`stripHtml(String input) → String`**: removes `<...>` tag patterns with regex, then collapses whitespace.

**`decodeXmlBytes(List<int> bytes) → String`**: encoding-aware bytes-to-string as described above.

**`resolveHref(String href, Uri base) → Uri`**: `base.resolve(href)`.

### Pagination

Feed-level `<link rel="next" ...>` → `nextPageUrl` (resolved against base). `Opds1FeedParser` always returns a single-page `ParsedFeed` including `nextPageUrl` when present. Multi-page merging and the 50-page safety cap are `FeedRepository` concerns (step 5).

---

## Unit 4: `Opds1Client` (`lib/data/opds1/opds1_client.dart`)

```dart
class Opds1Client implements OpdsClient {
  final OpdsHttpFetcher _fetcher;
  final OpdsFeedParser _parser;

  // Production: caller supplies an http.Client (e.g. http.Client())
  Opds1Client(http.Client httpClient)
      : _fetcher = OpdsHttpFetcher(httpClient),
        _parser = Opds1FeedParser();

  // Test: inject both dependencies directly
  Opds1Client.withDependencies(this._fetcher, this._parser);
}
```

**`fetchFeed(Uri url)`**: calls `_fetcher.fetch(url)` then `_parser.parse(bytes, url)`. `XmlException`/`FormatException` from the parser → `ParseException`. `NetworkException` and `HttpStatusException` from the fetcher propagate unchanged.

**`probe(Uri url)`**: calls `fetchFeed(url)`. Returns `true` on success. Returns `false` on `ParseException` or `UnsupportedProtocolException` (not an OPDS feed). Lets `NetworkException` and `HttpStatusException` propagate — those indicate connectivity failure, not "wrong format".

---

## Testing Strategy

### `test/data/opds1_feed_parser_test.dart`

No HTTP mocking needed. Load fixture bytes with `File('test/fixtures/foo.xml').readAsBytesSync()` and call `Opds1FeedParser().parse(bytes, feedUrl)`.

One group per fixture:

| Fixture | Assertions |
|---|---|
| `minimal_navigation_feed.xml` | 3 `NavigationEntry` items, correct titles and resolved URLs |
| `mixed_feed.xml` | entries interleaved in feed order (2 nav, 2 book), types correct |
| `empty_feed.xml` | zero entries, no next page |
| `malformed.xml` | throws `ParseException` |
| `book_multi_format_fb2.xml` | 4 `AcquisitionLink`s with correct labels, thumbnail cover URL |
| `book_no_fb2.xml` | 2 links, no FB2, correct labels |
| `series_calibre.xml` | series = "The Lord of the Rings", seriesIndex = 1.0 |
| `series_link.xml` | series = "The Lord of the Rings" via dcterms, seriesIndex null |
| `relative_hrefs.xml` | nav href resolves to absolute, acquisition href resolves via `../` |
| `windows1251.xml` | Russian titles decoded correctly to Unicode |
| `paginated_page1.xml` | `nextPageUrl` = `https://example.com/opds/books?page=2` |
| `paginated_page2.xml` | `nextPageUrl` is null |

Additional groups for pure functions: `mimeToLabel` (all 7 mappings + fallback), `extractSeries` (Calibre, dcterms, null), `stripHtml` (tags removed, whitespace collapsed), `decodeXmlBytes` (UTF-8 pass-through, windows-1251 round-trip).

### `test/data/opds1_client_test.dart`

Uses `MockClient` from `package:http/testing.dart`.

| Test | Setup → Expected outcome |
|---|---|
| Happy path | 200 + minimal nav bytes → `ParsedFeed` returned |
| HTTP 404 | 404 response → `HttpStatusException(404, ...)` |
| HTTP 401 | 401 response → `HttpStatusException(401, ...)` |
| Network error | `MockClient` throws `SocketException` → `NetworkException` |
| Timeout | delayed response beyond 20 s → `NetworkException` |
| Bad XML on 200 | non-OPDS body → `ParseException` |
| `probe` — valid OPDS | → `true` |
| `probe` — parse failure | → `false` |
| `probe` — network error | → `NetworkException` propagates |

---

## Constraints Carried Forward

- `Opds1FeedParser.parse()` is synchronous and pure — no I/O.
- No `flutter` imports anywhere in `lib/data/`.
- `dart run tool/check.dart` (analyze + test) must be green before the step is considered done.
- Single-page `ParsedFeed` only — pagination merging is step 5's concern.

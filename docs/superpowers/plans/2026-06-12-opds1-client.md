# Opds1Client — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `Opds1Client` — the concrete OPDS 1.x HTTP+XML implementation — split across four focused units: `OpdsFeedParser` interface, `OpdsHttpFetcher`, `Opds1FeedParser` (pure XML), and `Opds1Client` (wiring layer).

**Architecture:** `OpdsHttpFetcher` handles all HTTP concerns (fetch, timeout, User-Agent, error mapping) and returns raw bytes. `Opds1FeedParser` handles all XML parsing concerns (encoding detection, entry classification, URL resolution, series extraction). `Opds1Client` wires the two together and implements the domain `OpdsClient` interface. This split means OPDS 2.0 will only need a new parser — the HTTP layer and interface are reused unchanged.

**Tech Stack:** `package:http` (HTTP + `MockClient` for tests), `package:xml` (XML parsing), `dart:io` (SocketException), `dart:convert` (utf8 codec), `dart:io` (File for fixture loading in tests), `package:flutter_test`.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/data/opds_feed_parser.dart` | Create | `OpdsFeedParser` abstract interface |
| `lib/data/opds_http_fetcher.dart` | Create | HTTP transport: fetch, timeout, User-Agent, error mapping |
| `lib/data/opds1/opds1_feed_parser.dart` | Create | Pure XML→`ParsedFeed` conversion + all pure helper functions |
| `lib/data/opds1/opds1_client.dart` | Create | `Opds1Client implements OpdsClient` — wires fetcher + parser |
| `test/data/opds_http_fetcher_test.dart` | Create | Unit tests for `OpdsHttpFetcher` via `MockClient` |
| `test/data/opds1_feed_parser_test.dart` | Create | Unit tests for all pure functions + fixture-based parse tests |
| `test/data/opds1_client_test.dart` | Create | Unit tests for `Opds1Client` via `MockClient` |

---

## Task 1: `OpdsFeedParser` interface

**Files:**
- Create: `lib/data/opds_feed_parser.dart`

This interface is the contract between `OpdsHttpFetcher` (which returns bytes) and `Opds1FeedParser` (which consumes bytes). It has no behavior of its own so no unit test is written for it. The test gate still runs to confirm the file compiles cleanly.

- [ ] **Step 1.1 — Create `lib/data/opds_feed_parser.dart`**

```dart
import 'package:opds_browser/domain/models.dart';

abstract interface class OpdsFeedParser {
  /// Parses raw HTTP response [bytes] into a [ParsedFeed].
  /// [feedUrl] is the URL the bytes came from; used to resolve relative hrefs
  /// when [xml:base] is absent from the feed element.
  /// Throws [ParseException] on malformed or unrecognised content.
  ParsedFeed parse(List<int> bytes, Uri feedUrl);
}
```

- [ ] **Step 1.2 — Run the quality gate**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 1.3 — Commit**

```powershell
git add lib/data/opds_feed_parser.dart
git commit -m "feat(data): add OpdsFeedParser abstract interface"
```

---

## Task 2: `OpdsHttpFetcher`

**Files:**
- Create: `test/data/opds_http_fetcher_test.dart`
- Create: `lib/data/opds_http_fetcher.dart`

`OpdsHttpFetcher` takes an `http.Client` in its constructor (so tests can inject `MockClient`). It accepts an optional `timeout` parameter so tests don't wait 20 s for timeout assertions.

- [ ] **Step 2.1 — Write the failing tests**

Create `test/data/opds_http_fetcher_test.dart`:

```dart
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/opds_http_fetcher.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  final feedUrl = Uri.parse('https://example.com/opds');
  final minimalBody = utf8Body('<?xml version="1.0"?><feed/>');

  group('OpdsHttpFetcher', () {
    test('returns body bytes on 200', () async {
      final client = MockClient((_) async => http.Response.bytes(minimalBody, 200));
      final fetcher = OpdsHttpFetcher(client);
      final result = await fetcher.fetch(feedUrl);
      expect(result, minimalBody);
    });

    test('sends User-Agent header', () async {
      String? userAgent;
      final client = MockClient((req) async {
        userAgent = req.headers['User-Agent'];
        return http.Response.bytes(minimalBody, 200);
      });
      await OpdsHttpFetcher(client).fetch(feedUrl);
      expect(userAgent, 'OpdsBrowser/1.0');
    });

    test('throws HttpStatusException on 404', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      final fetcher = OpdsHttpFetcher(client);
      expect(
        fetcher.fetch(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('throws HttpStatusException on 401', () async {
      final client = MockClient((_) async => http.Response('Unauthorized', 401));
      final fetcher = OpdsHttpFetcher(client);
      expect(
        fetcher.fetch(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws NetworkException on SocketException', () async {
      final client = MockClient((_) async {
        throw const SocketException('Connection refused');
      });
      final fetcher = OpdsHttpFetcher(client);
      expect(fetcher.fetch(feedUrl), throwsA(isA<NetworkException>()));
    });

    test('throws NetworkException on timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response.bytes(minimalBody, 200);
      });
      final fetcher = OpdsHttpFetcher(
        client,
        timeout: const Duration(milliseconds: 100),
      );
      expect(fetcher.fetch(feedUrl), throwsA(isA<NetworkException>()));
    });
  });
}

List<int> utf8Body(String s) => dart_convert.utf8.encode(s);

// ignore: library_prefixes
import 'dart:convert' as dart_convert;
```

Wait — the import at the bottom is wrong placement. Rewrite cleanly:

```dart
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/opds_http_fetcher.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  final feedUrl = Uri.parse('https://example.com/opds');
  final minimalBody = utf8.encode('<?xml version="1.0"?><feed/>');

  group('OpdsHttpFetcher', () {
    test('returns body bytes on 200', () async {
      final client = MockClient((_) async => http.Response.bytes(minimalBody, 200));
      final result = await OpdsHttpFetcher(client).fetch(feedUrl);
      expect(result, minimalBody);
    });

    test('sends User-Agent header', () async {
      String? userAgent;
      final client = MockClient((req) async {
        userAgent = req.headers['User-Agent'];
        return http.Response.bytes(minimalBody, 200);
      });
      await OpdsHttpFetcher(client).fetch(feedUrl);
      expect(userAgent, 'OpdsBrowser/1.0');
    });

    test('throws HttpStatusException(404) on 404', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      expect(
        OpdsHttpFetcher(client).fetch(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('throws HttpStatusException(401) on 401', () async {
      final client = MockClient((_) async => http.Response('Unauthorized', 401));
      expect(
        OpdsHttpFetcher(client).fetch(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws NetworkException on SocketException', () async {
      final client = MockClient((_) async {
        throw const SocketException('Connection refused');
      });
      expect(
        OpdsHttpFetcher(client).fetch(feedUrl),
        throwsA(isA<NetworkException>()),
      );
    });

    test('throws NetworkException on timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response.bytes(minimalBody, 200);
      });
      expect(
        OpdsHttpFetcher(client, timeout: const Duration(milliseconds: 100))
            .fetch(feedUrl),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
```

- [ ] **Step 2.2 — Run to confirm compile failure**

```powershell
dart run tool/check.dart
```

Expected: compile error — `package:opds_browser/data/opds_http_fetcher.dart` not found.

- [ ] **Step 2.3 — Create `lib/data/opds_http_fetcher.dart`**

```dart
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:opds_browser/domain/opds_client.dart';

class OpdsHttpFetcher {
  final http.Client _client;
  final Duration _timeout;

  OpdsHttpFetcher(this._client, {Duration timeout = const Duration(seconds: 20)})
      : _timeout = timeout;

  Future<List<int>> fetch(Uri url) async {
    try {
      final response = await _client
          .get(url, headers: const {'User-Agent': 'OpdsBrowser/1.0'})
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpStatusException(
          response.statusCode,
          'HTTP ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw NetworkException('Request timed out after ${_timeout.inSeconds}s');
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    }
  }
}
```

- [ ] **Step 2.4 — Run to confirm all tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 2.5 — Commit**

```powershell
git add lib/data/opds_http_fetcher.dart test/data/opds_http_fetcher_test.dart
git commit -m "feat(data): add OpdsHttpFetcher with timeout and error mapping"
```

---

## Task 3: `Opds1FeedParser` scaffold + `mimeToLabel`

**Files:**
- Create: `test/data/opds1_feed_parser_test.dart`
- Create: `lib/data/opds1/opds1_feed_parser.dart`

`mimeToLabel` is a top-level pure function in `opds1_feed_parser.dart`. It's public so the test file can import and call it directly. The class itself is a stub at this stage — `parse()` throws `UnimplementedError` until Task 7.

- [ ] **Step 3.1 — Write the failing tests**

Create `test/data/opds1_feed_parser_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:opds_browser/data/opds1/opds1_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  group('mimeToLabel', () {
    test('maps application/fb2 → FB2', () =>
        expect(mimeToLabel('application/fb2'), 'FB2'));
    test('maps application/x-fictionbook+xml → FB2', () =>
        expect(mimeToLabel('application/x-fictionbook+xml'), 'FB2'));
    test('maps application/fb2+zip → FB2.ZIP', () =>
        expect(mimeToLabel('application/fb2+zip'), 'FB2.ZIP'));
    test('maps application/x-zip-compressed-fb2 → FB2.ZIP', () =>
        expect(mimeToLabel('application/x-zip-compressed-fb2'), 'FB2.ZIP'));
    test('maps application/epub+zip → EPUB', () =>
        expect(mimeToLabel('application/epub+zip'), 'EPUB'));
    test('maps application/pdf → PDF', () =>
        expect(mimeToLabel('application/pdf'), 'PDF'));
    test('maps application/x-mobipocket-ebook → MOBI', () =>
        expect(mimeToLabel('application/x-mobipocket-ebook'), 'MOBI'));
    test('maps unknown type to uppercase subtype', () =>
        expect(mimeToLabel('application/djvu'), 'DJVU'));
    test('maps application/x-cb7 → X-CB7 (uppercase subtype)', () =>
        expect(mimeToLabel('application/x-cb7'), 'X-CB7'));
  });
}
```

- [ ] **Step 3.2 — Run to confirm compile failure**

```powershell
dart run tool/check.dart
```

Expected: compile error — `package:opds_browser/data/opds1/opds1_feed_parser.dart` not found.

- [ ] **Step 3.3 — Create `lib/data/opds1/opds1_feed_parser.dart`**

```dart
import 'package:opds_browser/data/opds_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

String mimeToLabel(String mimeType) => switch (mimeType) {
      'application/fb2' || 'application/x-fictionbook+xml' => 'FB2',
      'application/fb2+zip' || 'application/x-zip-compressed-fb2' => 'FB2.ZIP',
      'application/epub+zip' => 'EPUB',
      'application/pdf' => 'PDF',
      'application/x-mobipocket-ebook' => 'MOBI',
      _ => mimeType.split('/').last.toUpperCase(),
    };

class Opds1FeedParser implements OpdsFeedParser {
  @override
  ParsedFeed parse(List<int> bytes, Uri feedUrl) =>
      throw UnimplementedError('parse not yet implemented');
}
```

- [ ] **Step 3.4 — Run to confirm tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 3.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): add Opds1FeedParser scaffold and mimeToLabel"
```

---

## Task 4: `decodeXmlBytes` (encoding support)

**Files:**
- Modify: `lib/data/opds1/opds1_feed_parser.dart`
- Modify: `test/data/opds1_feed_parser_test.dart`

`decodeXmlBytes` detects the encoding declared in the XML prolog and converts bytes to a Dart `String`. The windows-1251 mapping is a 128-entry lookup table covering bytes `0x80–0xFF`.

- [ ] **Step 4.1 — Add failing tests**

Append inside `main()` in `test/data/opds1_feed_parser_test.dart` (after the closing `});` of the `mimeToLabel` group):

```dart
  group('decodeXmlBytes', () {
    test('passes through UTF-8 bytes unchanged', () {
      const src = '<?xml version="1.0" encoding="UTF-8"?><root>Hello</root>';
      final result = decodeXmlBytes(utf8.encode(src));
      expect(result, src);
    });

    test('assumes UTF-8 when encoding attribute is absent', () {
      const src = '<?xml version="1.0"?><root>Test</root>';
      final result = decodeXmlBytes(utf8.encode(src));
      expect(result, src);
    });

    test('decodes windows-1251 fixture to correct Cyrillic text', () {
      final bytes =
          File('test/fixtures/windows1251.xml').readAsBytesSync().toList();
      final result = decodeXmlBytes(bytes);
      expect(result, contains('Кириллический каталог'));
      expect(result, contains('Мастер и Маргарита'));
      expect(result, contains('Михаил Булгаков'));
    });
  });
```

- [ ] **Step 4.2 — Run to confirm failure**

```powershell
dart run tool/check.dart
```

Expected: compile error — `decodeXmlBytes` not found.

- [ ] **Step 4.3 — Add `decodeXmlBytes` to `lib/data/opds1/opds1_feed_parser.dart`**

Replace the entire file contents with:

```dart
import 'dart:convert';

import 'package:opds_browser/data/opds_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

// Windows-1251 Unicode code points for bytes 0x80–0xFF (128 entries).
const _win1251 = <int>[
  // 0x80–0x87
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
  // 0x88–0x8F
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
  // 0x90–0x97
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  // 0x98–0x9F
  0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  // 0xA0–0xA7
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
  // 0xA8–0xAF
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  // 0xB0–0xB7
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
  // 0xB8–0xBF
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
  // 0xC0–0xC7: А Б В Г Д Е Ж З
  0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
  // 0xC8–0xCF: И Й К Л М Н О П
  0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
  // 0xD0–0xD7: Р С Т У Ф Х Ц Ч
  0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
  // 0xD8–0xDF: Ш Щ Ъ Ы Ь Э Ю Я
  0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
  // 0xE0–0xE7: а б в г д е ж з
  0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
  // 0xE8–0xEF: и й к л м н о п
  0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
  // 0xF0–0xF7: р с т у ф х ц ч
  0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
  // 0xF8–0xFF: ш щ ъ ы ь э ю я
  0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
];

/// Converts raw HTTP response [bytes] to a Dart [String].
/// Reads the encoding declaration from the XML prolog; defaults to UTF-8.
/// Supports windows-1251 via lookup table (no external dependency).
String decodeXmlBytes(List<int> bytes) {
  // Peek first 200 bytes as latin1 (ASCII-safe) to read the prolog.
  final prolog = String.fromCharCodes(bytes.take(200));
  final match = RegExp(r'''encoding=["']([^"']+)["']''', caseSensitive: false)
      .firstMatch(prolog);
  final declared = match?.group(1)?.toLowerCase() ?? 'utf-8';

  if (declared == 'utf-8' || declared == 'utf8') {
    return utf8.decode(bytes);
  }

  if (declared == 'windows-1251' ||
      declared == 'cp1251' ||
      declared == 'x-cp1251' ||
      declared == 'windows_1251') {
    return String.fromCharCodes(
      bytes.map((b) => b < 0x80 ? b : _win1251[b - 0x80]),
    );
  }

  // Unknown encoding: best-effort UTF-8.
  return utf8.decode(bytes, allowMalformed: true);
}

String mimeToLabel(String mimeType) => switch (mimeType) {
      'application/fb2' || 'application/x-fictionbook+xml' => 'FB2',
      'application/fb2+zip' || 'application/x-zip-compressed-fb2' => 'FB2.ZIP',
      'application/epub+zip' => 'EPUB',
      'application/pdf' => 'PDF',
      'application/x-mobipocket-ebook' => 'MOBI',
      _ => mimeType.split('/').last.toUpperCase(),
    };

class Opds1FeedParser implements OpdsFeedParser {
  @override
  ParsedFeed parse(List<int> bytes, Uri feedUrl) =>
      throw UnimplementedError('parse not yet implemented');
}
```

- [ ] **Step 4.4 — Run to confirm tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 4.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): add decodeXmlBytes with windows-1251 lookup table"
```

---

## Task 5: `stripHtml` + `resolveHref`

**Files:**
- Modify: `lib/data/opds1/opds1_feed_parser.dart`
- Modify: `test/data/opds1_feed_parser_test.dart`

- [ ] **Step 5.1 — Add failing tests**

Append inside `main()` after the `decodeXmlBytes` group:

```dart
  group('stripHtml', () {
    test('removes tags and collapses whitespace', () {
      expect(stripHtml('<p>Hello <b>world</b>.</p>'), 'Hello world.');
    });
    test('collapses internal whitespace', () {
      expect(stripHtml('One  two\n  three'), 'One two three');
    });
    test('returns empty string for tag-only input', () {
      expect(stripHtml('<br/>'), '');
    });
    test('passes plain text through untouched (trimmed)', () {
      expect(stripHtml('  plain text  '), 'plain text');
    });
  });

  group('resolveHref', () {
    final base = Uri.parse('https://example.com/catalog/');

    test('resolves relative path against base', () {
      expect(
        resolveHref('sub/', base),
        Uri.parse('https://example.com/catalog/sub/'),
      );
    });

    test('resolves parent-relative path against base', () {
      expect(
        resolveHref('../books/rel.epub', base),
        Uri.parse('https://example.com/books/rel.epub'),
      );
    });

    test('passes absolute href through unchanged', () {
      expect(
        resolveHref('https://other.com/feed', base),
        Uri.parse('https://other.com/feed'),
      );
    });
  });
```

- [ ] **Step 5.2 — Run to confirm failure**

```powershell
dart run tool/check.dart
```

Expected: compile error — `stripHtml` and `resolveHref` not found.

- [ ] **Step 5.3 — Add `stripHtml` and `resolveHref` to `lib/data/opds1/opds1_feed_parser.dart`**

Insert these two functions after `mimeToLabel` and before `class Opds1FeedParser`:

```dart
/// Strips HTML tags and collapses whitespace to single spaces.
String stripHtml(String input) => input
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Resolves [href] against [base] following RFC 3986.
Uri resolveHref(String href, Uri base) => base.resolve(href);
```

- [ ] **Step 5.4 — Run to confirm tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 5.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): add stripHtml and resolveHref pure functions"
```

---

## Task 6: `extractSeries`

**Files:**
- Modify: `lib/data/opds1/opds1_feed_parser.dart`
- Modify: `test/data/opds1_feed_parser_test.dart`

`extractSeries` takes an `XmlElement` (from `package:xml`) and returns a Dart record `({String? series, double? seriesIndex})`. Tests parse small inline XML strings to produce the element — no fixture files needed here.

- [ ] **Step 6.1 — Add failing tests**

Append inside `main()` after the `resolveHref` group:

```dart
  group('extractSeries', () {
    // Helper: parse an <entry> element from a minimal feed string.
    XmlElement parseEntry(String entryXml) => XmlDocument.parse(
          '<feed xmlns="http://www.w3.org/2005/Atom" '
          'xmlns:calibre="http://calibre.kovidgoyal.net/2009/#" '
          'xmlns:dcterms="http://purl.org/dc/terms/">'
          '$entryXml'
          '</feed>',
        ).rootElement.childElements.first;

    test('extracts Calibre series and index', () {
      final entry = parseEntry(
        '<entry>'
        '<calibre:series>My Series</calibre:series>'
        '<calibre:series_index>2.5</calibre:series_index>'
        '</entry>',
      );
      final result = extractSeries(entry);
      expect(result.series, 'My Series');
      expect(result.seriesIndex, 2.5);
    });

    test('Calibre series with integer index (1.0 stored as double)', () {
      final entry = parseEntry(
        '<entry>'
        '<calibre:series>Lord of the Rings</calibre:series>'
        '<calibre:series_index>1.0</calibre:series_index>'
        '</entry>',
      );
      final result = extractSeries(entry);
      expect(result.series, 'Lord of the Rings');
      expect(result.seriesIndex, 1.0);
    });

    test('extracts dcterms:isPartOf series (no index)', () {
      final entry = parseEntry(
        '<entry>'
        '<dcterms:isPartOf>My DC Series</dcterms:isPartOf>'
        '</entry>',
      );
      final result = extractSeries(entry);
      expect(result.series, 'My DC Series');
      expect(result.seriesIndex, isNull);
    });

    test('Calibre takes precedence over dcterms when both present', () {
      final entry = parseEntry(
        '<entry>'
        '<calibre:series>Calibre Series</calibre:series>'
        '<calibre:series_index>3.0</calibre:series_index>'
        '<dcterms:isPartOf>DC Series</dcterms:isPartOf>'
        '</entry>',
      );
      final result = extractSeries(entry);
      expect(result.series, 'Calibre Series');
    });

    test('returns null series and index when no series metadata present', () {
      final entry = parseEntry('<entry><title>Plain Book</title></entry>');
      final result = extractSeries(entry);
      expect(result.series, isNull);
      expect(result.seriesIndex, isNull);
    });
  });
```

- [ ] **Step 6.2 — Run to confirm failure**

```powershell
dart run tool/check.dart
```

Expected: compile error — `extractSeries` not found.

- [ ] **Step 6.3 — Add imports and `extractSeries` to `lib/data/opds1/opds1_feed_parser.dart`**

Add `import 'package:xml/xml.dart';` at the top (after `import 'dart:convert';`).

Add these constants after the `resolveHref` function and before `class Opds1FeedParser`:

```dart
const _calibreNs = 'http://calibre.kovidgoyal.net/2009/#';
const _dctermsNs = 'http://purl.org/dc/terms/';
const _xmlNs = 'http://www.w3.org/XML/1998/namespace';
const _acqRelPrefix = 'http://opds-spec.org/acquisition';
const _thumbRel = 'http://opds-spec.org/image/thumbnail';
const _imageRel = 'http://opds-spec.org/image';
```

Add the `extractSeries` function after the constants:

```dart
/// Extracts series name and index from an OPDS entry element.
/// Checks Calibre namespace first, then dcterms:isPartOf.
/// Returns (series: null, seriesIndex: null) when no series metadata found.
({String? series, double? seriesIndex}) extractSeries(XmlElement entry) {
  // 1. Calibre namespace: <calibre:series> + <calibre:series_index>
  final calibreSeries = entry.childElements
      .where((e) => e.localName == 'series' && e.namespaceUri == _calibreNs)
      .firstOrNull;
  if (calibreSeries != null) {
    final name = calibreSeries.innerText.trim();
    if (name.isNotEmpty) {
      final indexEl = entry.childElements
          .where(
              (e) => e.localName == 'series_index' && e.namespaceUri == _calibreNs)
          .firstOrNull;
      final index =
          indexEl != null ? double.tryParse(indexEl.innerText.trim()) : null;
      return (series: name, seriesIndex: index);
    }
  }

  // 2. dcterms:isPartOf
  final dcterms = entry.childElements
      .where((e) => e.localName == 'isPartOf' && e.namespaceUri == _dctermsNs)
      .firstOrNull;
  if (dcterms != null) {
    final name = dcterms.innerText.trim();
    if (name.isNotEmpty) return (series: name, seriesIndex: null);
  }

  return (series: null, seriesIndex: null);
}
```

- [ ] **Step 6.4 — Run to confirm tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 6.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): add extractSeries (Calibre and dcterms variants)"
```

---

## Task 7: `Opds1FeedParser.parse` — scaffold + navigation feeds + errors

**Files:**
- Modify: `lib/data/opds1/opds1_feed_parser.dart`
- Modify: `test/data/opds1_feed_parser_test.dart`

The parse method is implemented. Book entries return `null` from `_parseEntry` at this stage (added in Task 8). Tests cover: navigation feeds, empty feed, malformed XML.

The current working directory when `flutter test` runs is the project root (where `pubspec.yaml` lives), so `File('test/fixtures/foo.xml')` resolves correctly.

- [ ] **Step 7.1 — Add failing fixture tests**

Append inside `main()` after the `extractSeries` group:

```dart
  group('Opds1FeedParser.parse — navigation feeds', () {
    final parser = Opds1FeedParser();
    final base = Uri.parse('https://example.com/opds');

    test('parses minimal navigation feed — 3 entries in order', () {
      final bytes =
          File('test/fixtures/minimal_navigation_feed.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);

      expect(feed.title, 'Test Navigation Feed');
      expect(feed.entries.length, 3);
      expect(feed.nextPageUrl, isNull);

      final first = feed.entries[0] as NavigationEntry;
      expect(first.title, 'Science Fiction');
      expect(first.subtitle, 'Sci-fi books');
      expect(first.url, Uri.parse('https://example.com/opds/sci-fi'));

      final second = feed.entries[1] as NavigationEntry;
      expect(second.title, 'Fantasy');
      expect(second.subtitle, isNull);
      expect(second.url, Uri.parse('https://example.com/opds/fantasy'));

      final third = feed.entries[2] as NavigationEntry;
      expect(third.title, 'Mystery');
      expect(third.url, Uri.parse('https://example.com/opds/mystery'));
    });

    test('parses empty feed — zero entries', () {
      final bytes = File('test/fixtures/empty_feed.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);
      expect(feed.title, 'Empty Feed');
      expect(feed.entries, isEmpty);
      expect(feed.nextPageUrl, isNull);
    });

    test('malformed XML throws ParseException', () {
      final bytes = File('test/fixtures/malformed.xml').readAsBytesSync();
      expect(
        () => parser.parse(bytes, base),
        throwsA(isA<ParseException>()),
      );
    });
  });
```

- [ ] **Step 7.2 — Run to confirm failure**

```powershell
dart run tool/check.dart
```

Expected: tests fail with `UnimplementedError` from the parse stub.

- [ ] **Step 7.3 — Replace the `Opds1FeedParser` class in `lib/data/opds1/opds1_feed_parser.dart`**

Replace the current `class Opds1FeedParser` with:

```dart
class Opds1FeedParser implements OpdsFeedParser {
  @override
  ParsedFeed parse(List<int> bytes, Uri feedUrl) {
    final xmlString = decodeXmlBytes(bytes);
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlString);
    } on XmlException catch (e) {
      throw ParseException('XML parse error: $e');
    }

    final feed = doc.rootElement;
    if (feed.localName != 'feed') {
      throw ParseException('Root element is not <feed>');
    }

    // Effective base URL: xml:base on <feed> takes precedence over feedUrl.
    final baseAttr = feed.getAttribute('base', namespace: _xmlNs);
    final base = baseAttr != null ? feedUrl.resolve(baseAttr) : feedUrl;

    final titleEl =
        feed.childElements.where((e) => e.localName == 'title').firstOrNull;
    final title = titleEl?.innerText.trim() ?? '';

    // Feed-level rel="next" link → nextPageUrl.
    Uri? nextPageUrl;
    for (final link
        in feed.childElements.where((e) => e.localName == 'link')) {
      if (link.getAttribute('rel') == 'next') {
        final href = link.getAttribute('href');
        if (href != null) nextPageUrl = resolveHref(href, base);
        break;
      }
    }

    final entries = <FeedEntry>[];
    for (final entry
        in feed.childElements.where((e) => e.localName == 'entry')) {
      final parsed = _parseEntry(entry, base);
      if (parsed != null) entries.add(parsed);
    }

    return ParsedFeed(title: title, entries: entries, nextPageUrl: nextPageUrl);
  }

  FeedEntry? _parseEntry(XmlElement entry, Uri base) {
    final links =
        entry.childElements.where((e) => e.localName == 'link').toList();

    final hasAcquisition = links.any((l) {
      final rel = l.getAttribute('rel') ?? '';
      return rel.startsWith(_acqRelPrefix);
    });
    // Book entry implementation added in Task 8.
    if (hasAcquisition) return null;

    final hasNav = links.any((l) {
      final type = l.getAttribute('type') ?? '';
      return type.contains('application/atom+xml');
    });
    if (hasNav) return _parseNavEntry(entry, links, base);

    return null;
  }

  NavigationEntry _parseNavEntry(
      XmlElement entry, List<XmlElement> links, Uri base) {
    final title = entry.childElements
            .where((e) => e.localName == 'title')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';

    final subtitleRaw = entry.childElements
        .where((e) => e.localName == 'content' || e.localName == 'summary')
        .firstOrNull
        ?.innerText
        .trim();
    final subtitle =
        (subtitleRaw == null || subtitleRaw.isEmpty) ? null : subtitleRaw;

    final navLink = links.firstWhere(
      (l) => (l.getAttribute('type') ?? '').contains('application/atom+xml'),
    );
    final href = navLink.getAttribute('href') ?? '';
    return NavigationEntry(
      title: title,
      subtitle: subtitle,
      url: resolveHref(href, base),
    );
  }
}
```

- [ ] **Step 7.4 — Run to confirm tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 7.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): implement Opds1FeedParser.parse for navigation feeds"
```

---

## Task 8: `Opds1FeedParser.parse` — book entries

**Files:**
- Modify: `lib/data/opds1/opds1_feed_parser.dart`
- Modify: `test/data/opds1_feed_parser_test.dart`

Book entries have acquisition links, authors, summary, and cover URL. Series is left null at this stage and wired in Task 9.

- [ ] **Step 8.1 — Add failing fixture tests**

Append inside `main()` after the `navigation feeds` group:

```dart
  group('Opds1FeedParser.parse — book entries', () {
    final parser = Opds1FeedParser();
    final base = Uri.parse('https://example.com/opds');

    test('multi-format book — all 4 acquisition links, thumbnail cover', () {
      final bytes =
          File('test/fixtures/book_multi_format_fb2.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);

      expect(feed.entries.length, 1);
      final book = feed.entries.first as BookEntry;
      expect(book.title, 'Sample Book');
      expect(book.authors, ['Alice Author', 'Bob Coauthor']);
      expect(book.summary, 'A book available in multiple formats.');
      expect(book.coverUrl,
          Uri.parse('https://example.com/covers/sample-thumb.jpg'));

      final labels = book.acquisitionLinks.map((l) => l.formatLabel).toList();
      expect(labels, ['FB2', 'FB2.ZIP', 'EPUB', 'PDF']);

      final urls = book.acquisitionLinks.map((l) => l.url.toString()).toList();
      expect(urls, [
        'https://example.com/books/sample.fb2',
        'https://example.com/books/sample.fb2.zip',
        'https://example.com/books/sample.epub',
        'https://example.com/books/sample.pdf',
      ]);
    });

    test('book with no FB2 — 2 links, EPUB and PDF labels', () {
      final bytes = File('test/fixtures/book_no_fb2.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);

      final book = feed.entries.first as BookEntry;
      expect(book.title, 'EPUB Only Book');
      expect(book.authors, ['Carol Writer']);
      expect(book.summary, 'This book has no FB2 format.');
      expect(book.coverUrl, isNull);

      final labels = book.acquisitionLinks.map((l) => l.formatLabel).toList();
      expect(labels, ['EPUB', 'PDF']);
    });

    test('mixed feed — entries in feed order, nav and book interleaved', () {
      final bytes = File('test/fixtures/mixed_feed.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);

      expect(feed.entries.length, 4);
      expect(feed.entries[0], isA<NavigationEntry>());
      expect((feed.entries[0] as NavigationEntry).title, 'New Arrivals');

      expect(feed.entries[1], isA<BookEntry>());
      final dart = feed.entries[1] as BookEntry;
      expect(dart.title, 'The Dart Programming Language');
      expect(dart.authors, ['John Doe']);
      expect(dart.summary, 'A book about Dart.');
      expect(dart.coverUrl,
          Uri.parse('https://example.com/covers/dart-thumb.jpg'));
      expect(dart.acquisitionLinks.first.formatLabel, 'EPUB');

      expect(feed.entries[2], isA<NavigationEntry>());
      expect((feed.entries[2] as NavigationEntry).title, 'Top Rated');

      expect(feed.entries[3], isA<BookEntry>());
      final flutter = feed.entries[3] as BookEntry;
      expect(flutter.title, 'Flutter in Action');
      expect(flutter.authors, ['Jane Smith']);
      expect(flutter.acquisitionLinks.first.formatLabel, 'FB2');
    });
  });
```

- [ ] **Step 8.2 — Run to confirm failure**

```powershell
dart run tool/check.dart
```

Expected: tests fail — book entries currently return `null` from `_parseEntry`.

- [ ] **Step 8.3 — Add `_parseBookEntry` and wire it into `_parseEntry`**

Inside `class Opds1FeedParser`, replace the line `if (hasAcquisition) return null;` with:

```dart
    if (hasAcquisition) return _parseBookEntry(entry, links, base);
```

Then add this private method at the end of the class (after `_parseNavEntry`):

```dart
  BookEntry _parseBookEntry(
      XmlElement entry, List<XmlElement> links, Uri base) {
    final title = entry.childElements
            .where((e) => e.localName == 'title')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';

    final authors = entry.childElements
        .where((e) => e.localName == 'author')
        .map((a) => a.childElements
            .where((e) => e.localName == 'name')
            .firstOrNull
            ?.innerText
            .trim())
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();

    final summaryEl =
        entry.childElements.where((e) => e.localName == 'summary').firstOrNull;
    final summary =
        summaryEl != null ? stripHtml(summaryEl.innerText) : null;

    // Cover: prefer thumbnail, fall back to full image.
    Uri? coverUrl;
    final thumbLink =
        links.where((l) => l.getAttribute('rel') == _thumbRel).firstOrNull;
    if (thumbLink != null) {
      final href = thumbLink.getAttribute('href');
      if (href != null) coverUrl = resolveHref(href, base);
    } else {
      final imgLink =
          links.where((l) => l.getAttribute('rel') == _imageRel).firstOrNull;
      if (imgLink != null) {
        final href = imgLink.getAttribute('href');
        if (href != null) coverUrl = resolveHref(href, base);
      }
    }

    final acquisitionLinks = links
        .where((l) {
          final rel = l.getAttribute('rel') ?? '';
          return rel.startsWith(_acqRelPrefix);
        })
        .map((l) {
          final href = l.getAttribute('href') ?? '';
          final mimeType = l.getAttribute('type') ?? '';
          return AcquisitionLink(
            url: resolveHref(href, base),
            mimeType: mimeType,
            formatLabel: mimeToLabel(mimeType),
          );
        })
        .toList();

    return BookEntry(
      title: title,
      authors: authors,
      series: null,
      seriesIndex: null,
      summary: summary?.isEmpty == true ? null : summary,
      coverUrl: coverUrl,
      acquisitionLinks: acquisitionLinks,
    );
  }
```

- [ ] **Step 8.4 — Run to confirm tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 8.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): implement _parseBookEntry (authors, cover, links)"
```

---

## Task 9: Series metadata, relative hrefs, windows-1251

**Files:**
- Modify: `lib/data/opds1/opds1_feed_parser.dart`
- Modify: `test/data/opds1_feed_parser_test.dart`

The `xml:base` URL resolution and `decodeXmlBytes` encoding handling are already wired into `parse()` from Tasks 4 and 7 — the relative-hrefs and windows-1251 tests should pass once book entry parsing is complete. Only series support needs a code change.

- [ ] **Step 9.1 — Add failing fixture tests**

Append inside `main()` after the `book entries` group:

```dart
  group('Opds1FeedParser.parse — series + URL resolution + encoding', () {
    final parser = Opds1FeedParser();
    final base = Uri.parse('https://example.com/opds');

    test('Calibre series — name and index extracted', () {
      final bytes =
          File('test/fixtures/series_calibre.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);
      final book = feed.entries.first as BookEntry;
      expect(book.title, 'The Fellowship of the Ring');
      expect(book.series, 'The Lord of the Rings');
      expect(book.seriesIndex, 1.0);
    });

    test('dcterms:isPartOf series — name extracted, index null', () {
      final bytes = File('test/fixtures/series_link.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);
      final book = feed.entries.first as BookEntry;
      expect(book.title, 'The Two Towers');
      expect(book.series, 'The Lord of the Rings');
      expect(book.seriesIndex, isNull);
    });

    test('relative hrefs — resolved against xml:base', () {
      final bytes =
          File('test/fixtures/relative_hrefs.xml').readAsBytesSync();
      // feedUrl is irrelevant here — xml:base="https://example.com/catalog/" overrides.
      final feed =
          parser.parse(bytes, Uri.parse('https://example.com/opds'));

      final nav = feed.entries[0] as NavigationEntry;
      expect(nav.url, Uri.parse('https://example.com/catalog/sub/'));

      final book = feed.entries[1] as BookEntry;
      expect(book.acquisitionLinks.first.url,
          Uri.parse('https://example.com/books/rel.epub'));
    });

    test('windows-1251 feed — Cyrillic text decoded correctly', () {
      final bytes =
          File('test/fixtures/windows1251.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);

      expect(feed.title, 'Кириллический каталог');
      final book = feed.entries.first as BookEntry;
      expect(book.title, 'Мастер и Маргарита');
      expect(book.authors, ['Михаил Булгаков']);
    });
  });
```

- [ ] **Step 9.2 — Run to confirm series tests fail (others may pass)**

```powershell
dart run tool/check.dart
```

Expected: series tests fail (`book.series` is `null`); relative-hrefs and windows-1251 tests pass.

- [ ] **Step 9.3 — Wire `extractSeries` into `_parseBookEntry`**

In `_parseBookEntry`, replace:

```dart
    return BookEntry(
      title: title,
      authors: authors,
      series: null,
      seriesIndex: null,
```

with:

```dart
    final (:series, :seriesIndex) = extractSeries(entry);
    return BookEntry(
      title: title,
      authors: authors,
      series: series,
      seriesIndex: seriesIndex,
```

- [ ] **Step 9.4 — Run to confirm all tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 9.5 — Commit**

```powershell
git add lib/data/opds1/opds1_feed_parser.dart test/data/opds1_feed_parser_test.dart
git commit -m "feat(data): wire extractSeries into book entry parsing"
```

---

## Task 10: Pagination

**Files:**
- Modify: `test/data/opds1_feed_parser_test.dart`

The `rel="next"` link extraction was already implemented in Task 7's `parse()` method. These tests verify the implementation is correct — no code change is expected.

- [ ] **Step 10.1 — Add fixture tests**

Append inside `main()` after the `series + URL resolution + encoding` group:

```dart
  group('Opds1FeedParser.parse — pagination', () {
    final parser = Opds1FeedParser();
    final base = Uri.parse('https://example.com/opds/books');

    test('page 1 — nextPageUrl points to page 2', () {
      final bytes =
          File('test/fixtures/paginated_page1.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);
      expect(feed.title, 'Paginated Feed — Page 1');
      expect(feed.entries.length, 5);
      expect(feed.nextPageUrl,
          Uri.parse('https://example.com/opds/books?page=2'));
    });

    test('page 2 — nextPageUrl is null (last page)', () {
      final bytes =
          File('test/fixtures/paginated_page2.xml').readAsBytesSync();
      final feed = parser.parse(bytes, base);
      expect(feed.title, 'Paginated Feed — Page 2');
      expect(feed.entries.length, 5);
      expect(feed.nextPageUrl, isNull);
    });
  });
```

- [ ] **Step 10.2 — Run to confirm tests pass without code changes**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.` (The `nextPageUrl` logic was implemented in Task 7.)

- [ ] **Step 10.3 — Commit**

```powershell
git add test/data/opds1_feed_parser_test.dart
git commit -m "test(data): add pagination fixture tests for Opds1FeedParser"
```

---

## Task 11: `Opds1Client`

**Files:**
- Create: `test/data/opds1_client_test.dart`
- Create: `lib/data/opds1/opds1_client.dart`

`Opds1Client` implements `OpdsClient` by wiring `OpdsHttpFetcher` + `Opds1FeedParser`. Its primary constructor accepts `http.Client`; the `withDependencies` named constructor enables injecting mock collaborators in tests. In the tests below we use the primary constructor with a `MockClient`, which exercises the real fetcher and parser together.

- [ ] **Step 11.1 — Write the failing tests**

Create `test/data/opds1_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

// Minimal valid OPDS Atom feed used as the "happy path" response body.
final _validFeedBytes = utf8.encode(
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<feed xmlns="http://www.w3.org/2005/Atom">'
  '<title>Test Feed</title>'
  '<entry>'
  '<title>Sub-folder</title>'
  '<link rel="subsection" '
  'type="application/atom+xml;profile=opds-catalog" '
  'href="https://example.com/opds/sub"/>'
  '</entry>'
  '</feed>',
);

void main() {
  final feedUrl = Uri.parse('https://example.com/opds');

  group('Opds1Client.fetchFeed', () {
    test('returns ParsedFeed on 200 with valid OPDS XML', () async {
      final client = MockClient((_) async =>
          http.Response.bytes(_validFeedBytes, 200));
      final opds = Opds1Client(client);
      final feed = await opds.fetchFeed(feedUrl);
      expect(feed, isA<ParsedFeed>());
      expect(feed.title, 'Test Feed');
      expect(feed.entries.length, 1);
      expect(feed.entries.first, isA<NavigationEntry>());
    });

    test('throws HttpStatusException on 404', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      final opds = Opds1Client(client);
      expect(
        opds.fetchFeed(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('throws HttpStatusException on 401', () async {
      final client = MockClient((_) async => http.Response('Unauthorized', 401));
      final opds = Opds1Client(client);
      expect(
        opds.fetchFeed(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws NetworkException on SocketException', () async {
      final client = MockClient((_) async {
        throw const SocketException('No route to host');
      });
      final opds = Opds1Client(client);
      expect(opds.fetchFeed(feedUrl), throwsA(isA<NetworkException>()));
    });

    test('throws ParseException when 200 body is not valid OPDS XML', () async {
      final client = MockClient((_) async =>
          http.Response.bytes(utf8.encode('not xml at all'), 200));
      final opds = Opds1Client(client);
      expect(opds.fetchFeed(feedUrl), throwsA(isA<ParseException>()));
    });
  });

  group('Opds1Client.probe', () {
    test('returns true for valid OPDS feed', () async {
      final client = MockClient((_) async =>
          http.Response.bytes(_validFeedBytes, 200));
      expect(await Opds1Client(client).probe(feedUrl), isTrue);
    });

    test('returns false when body is not parseable as OPDS', () async {
      final client = MockClient((_) async =>
          http.Response.bytes(utf8.encode('not xml'), 200));
      expect(await Opds1Client(client).probe(feedUrl), isFalse);
    });

    test('propagates NetworkException (not swallowed by probe)', () async {
      final client = MockClient((_) async {
        throw const SocketException('Connection refused');
      });
      expect(
        Opds1Client(client).probe(feedUrl),
        throwsA(isA<NetworkException>()),
      );
    });

    test('propagates HttpStatusException (not swallowed by probe)', () async {
      final client = MockClient((_) async => http.Response('Error', 500));
      expect(
        Opds1Client(client).probe(feedUrl),
        throwsA(isA<HttpStatusException>()),
      );
    });
  });
}
```

- [ ] **Step 11.2 — Run to confirm compile failure**

```powershell
dart run tool/check.dart
```

Expected: compile error — `package:opds_browser/data/opds1/opds1_client.dart` not found.

- [ ] **Step 11.3 — Create `lib/data/opds1/opds1_client.dart`**

```dart
import 'package:http/http.dart' as http;
import 'package:opds_browser/data/opds_feed_parser.dart';
import 'package:opds_browser/data/opds_http_fetcher.dart';
import 'package:opds_browser/data/opds1/opds1_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

class Opds1Client implements OpdsClient {
  final OpdsHttpFetcher _fetcher;
  final OpdsFeedParser _parser;

  /// Production constructor: wraps [httpClient] in an [OpdsHttpFetcher]
  /// and uses the default [Opds1FeedParser].
  Opds1Client(http.Client httpClient)
      : _fetcher = OpdsHttpFetcher(httpClient),
        _parser = Opds1FeedParser();

  /// Test constructor: inject both collaborators directly.
  Opds1Client.withDependencies(this._fetcher, this._parser);

  @override
  Future<ParsedFeed> fetchFeed(Uri url) async {
    final bytes = await _fetcher.fetch(url);
    return _parser.parse(bytes, url);
  }

  @override
  Future<bool> probe(Uri url) async {
    try {
      await fetchFeed(url);
      return true;
    } on ParseException {
      return false;
    } on UnsupportedProtocolException {
      return false;
    }
    // NetworkException and HttpStatusException propagate to caller.
  }
}
```

- [ ] **Step 11.4 — Run to confirm all tests pass**

```powershell
dart run tool/check.dart
```

Expected last line: `All checks passed.`

- [ ] **Step 11.5 — Commit**

```powershell
git add lib/data/opds1/opds1_client.dart test/data/opds1_client_test.dart
git commit -m "feat(data): add Opds1Client implementing OpdsClient"
```

---

## Self-Review

**Spec coverage check against §4.3:**

| Requirement | Task |
|---|---|
| Parse Atom feeds, be lenient | Task 7 — localName matching, no namespace enforcement |
| BookEntry classification (rel starts with acquisition prefix) | Task 7 `_parseEntry` |
| NavigationEntry classification (type contains atom+xml) | Task 7 `_parseEntry` |
| Drop entries with neither | Task 7 `_parseEntry` returns null |
| URL resolution against feed URL / xml:base | Tasks 7 + 9 |
| Authors: all `<author><name>` in order | Task 8 `_parseBookEntry` |
| Series: Calibre namespace | Task 6 `extractSeries` + Task 9 wiring |
| Series: dcterms:isPartOf | Task 6 `extractSeries` + Task 9 wiring |
| Cover: thumbnail preferred over full image | Task 8 `_parseBookEntry` |
| Pagination: rel="next" → nextPageUrl | Task 7 `parse()`, tested Task 10 |
| Mime → label mapping | Task 3 `mimeToLabel` |
| Encoding: windows-1251 | Task 4 `decodeXmlBytes`, tested Task 9 |
| Network 20 s timeout | Task 2 `OpdsHttpFetcher` |
| User-Agent header | Task 2 `OpdsHttpFetcher` |
| Follow redirects (≤5) | Task 2 — delegated to `http.IOClient` default |
| `OpdsException` error taxonomy | Tasks 2 + 11 |
| `probe` returns false for non-OPDS | Task 11 |
| `probe` propagates network errors | Task 11 |
| Pure function `extractSeries` with thorough tests | Task 6 (5 test cases) |

**Type consistency check:** `OpdsFeedParser.parse(List<int>, Uri)` → used in Task 1 (interface), Task 3 (stub), Tasks 7–10 (implementation), Task 11 (`Opds1Client.fetchFeed`). Consistent throughout. `OpdsHttpFetcher.fetch(Uri) → Future<List<int>>` matches usage in `Opds1Client`. `extractSeries` returns `({String? series, double? seriesIndex})` — used via destructuring in Task 9. Consistent.

**No placeholders found.**

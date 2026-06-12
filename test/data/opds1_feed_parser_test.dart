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
}

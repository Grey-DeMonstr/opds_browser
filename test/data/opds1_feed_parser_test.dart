import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart'; // ignore: unused_import
import 'package:opds_browser/data/opds1/opds1_feed_parser.dart';
import 'package:opds_browser/domain/models.dart'; // ignore: unused_import
import 'package:opds_browser/domain/opds_client.dart'; // ignore: unused_import

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
}

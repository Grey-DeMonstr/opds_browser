import 'dart:convert'; // ignore: unused_import
import 'dart:io'; // ignore: unused_import

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
}

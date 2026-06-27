import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/fb2_metadata_parser.dart';

const _singleAuthorXml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><first-name>Jane</first-name><middle-name>Marie</middle-name><last-name>Doe</last-name></author>
<book-title>My Book</book-title>
<sequence name="My Series" number="3"/>
</title-info></description>
<body><section><p>Text</p></section></body>
</FictionBook>''';

const _multiAuthorXml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><first-name>John</first-name><last-name>Smith</last-name></author>
<author><first-name>Jane</first-name><last-name>Doe</last-name></author>
<book-title>Joint Work</book-title>
</title-info></description>
<body><section><p>Text</p></section></body>
</FictionBook>''';

const _noSeriesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><last-name>Doe</last-name></author>
<book-title>Standalone</book-title>
</title-info></description>
<body><section><p>Text</p></section></body>
</FictionBook>''';

const _lastNameOnlyXml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><last-name>Tolstoy</last-name></author>
<book-title>War</book-title>
<sequence name="Epic" number="1"/>
</title-info></description>
<body><section><p>Text</p></section></body>
</FictionBook>''';

Uint8List _makeZip(String fb2Xml) {
  final bytes = utf8.encode(fb2Xml);
  final archive = Archive()
    ..addFile(ArchiveFile('book.fb2', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  late Fb2MetadataParser parser;
  setUp(() => parser = Fb2MetadataParser());

  group('parseXml', () {
    test('single author with first+middle+last joined', () {
      final meta = parser.parseXml(_singleAuthorXml);
      expect(meta.author, 'Jane Marie Doe');
    });

    test('multiple authors joined with comma', () {
      final meta = parser.parseXml(_multiAuthorXml);
      expect(meta.author, 'John Smith, Jane Doe');
    });

    test('last-name-only author', () {
      final meta = parser.parseXml(_lastNameOnlyXml);
      expect(meta.author, 'Tolstoy');
    });

    test('title extracted', () {
      final meta = parser.parseXml(_singleAuthorXml);
      expect(meta.title, 'My Book');
    });

    test('series name and number extracted', () {
      final meta = parser.parseXml(_singleAuthorXml);
      expect(meta.series, 'My Series');
      expect(meta.seriesIndex, 3);
    });

    test('no series yields null series and seriesIndex', () {
      final meta = parser.parseXml(_noSeriesXml);
      expect(meta.series, isNull);
      expect(meta.seriesIndex, isNull);
    });

    test('throws FormatException on malformed XML', () {
      expect(
        () => parser.parseXml('<not valid xml>>>'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parseBytes — fb2', () {
    test('parses plain fb2 bytes', () {
      final bytes = Uint8List.fromList(utf8.encode(_singleAuthorXml));
      final meta = parser.parseBytes(bytes);
      expect(meta.title, 'My Book');
      expect(meta.author, 'Jane Marie Doe');
    });
  });

  group('parseBytes — fb2.zip', () {
    test('decompresses zip and parses fb2 inside', () {
      final zipBytes = _makeZip(_singleAuthorXml);
      final meta = parser.parseBytes(zipBytes, isZip: true);
      expect(meta.title, 'My Book');
      expect(meta.series, 'My Series');
    });

    test('throws FormatException when no .fb2 in zip', () {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 5, [104, 101, 108, 108, 111]));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(
        () => parser.parseBytes(zipBytes, isZip: true),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

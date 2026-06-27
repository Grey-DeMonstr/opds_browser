import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/fb2_metadata_parser.dart';
import 'package:opds_browser/data/fb2_metadata_writer.dart';
import 'package:opds_browser/domain/local_library.dart';

const _baseXml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><first-name>Jane</first-name><last-name>Doe</last-name></author>
<book-title>Old Title</book-title>
<sequence name="Old Series" number="2"/>
</title-info></description>
<body><section><p>Body text unchanged</p></section></body>
</FictionBook>''';

const _noSeriesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><last-name>Smith</last-name></author>
<book-title>No Series Book</book-title>
</title-info></description>
<body><section><p>Body</p></section></body>
</FictionBook>''';

Uint8List _makeZip(String fb2Xml) {
  final bytes = utf8.encode(fb2Xml);
  final archive = Archive()
    ..addFile(ArchiveFile('book.fb2', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  final parser = Fb2MetadataParser();
  late Fb2MetadataWriter writer;
  setUp(() => writer = Fb2MetadataWriter());

  group('patchXml', () {
    test('round-trip: title updated', () {
      const newMeta = LocalBookMetadata(
        title: 'New Title',
        author: 'Jane Doe',
        series: 'Old Series',
        seriesIndex: 2,
      );
      final patched = writer.patchXml(_baseXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.title, 'New Title');
    });

    test('round-trip: author updated as single last-name field', () {
      const newMeta = LocalBookMetadata(
        title: 'Old Title',
        author: 'John Smith',
        series: 'Old Series',
        seriesIndex: 2,
      );
      final patched = writer.patchXml(_baseXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.author, 'John Smith');
    });

    test('comma-separated author stored as single last-name string', () {
      const newMeta = LocalBookMetadata(title: 'T', author: 'Tolkien, Lewis');
      final patched = writer.patchXml(_noSeriesXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.author, 'Tolkien, Lewis');
    });

    test('round-trip: series and seriesIndex updated', () {
      const newMeta = LocalBookMetadata(
        title: 'Old Title',
        author: 'Jane Doe',
        series: 'New Series',
        seriesIndex: 5,
      );
      final patched = writer.patchXml(_baseXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.series, 'New Series');
      expect(reparsed.seriesIndex, 5);
    });

    test('clearing series removes sequence element', () {
      const newMeta = LocalBookMetadata(title: 'Old Title', author: 'Jane Doe');
      final patched = writer.patchXml(_baseXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.series, isNull);
      expect(reparsed.seriesIndex, isNull);
    });

    test('adding series to a book that had none', () {
      const newMeta = LocalBookMetadata(
        title: 'No Series Book',
        author: 'Smith',
        series: 'Added Series',
        seriesIndex: 1,
      );
      final patched = writer.patchXml(_noSeriesXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.series, 'Added Series');
      expect(reparsed.seriesIndex, 1);
    });

    test('body text is preserved unchanged', () {
      const newMeta = LocalBookMetadata(title: 'New', author: 'Author');
      final patched = writer.patchXml(_baseXml, newMeta);
      expect(patched, contains('Body text unchanged'));
    });
  });

  group('patchBytes — fb2.zip', () {
    test('patches metadata inside zip and reparseable', () {
      final zipBytes = _makeZip(_baseXml);
      const newMeta = LocalBookMetadata(
        title: 'Zipped New',
        author: 'Zip Author',
        series: 'Zip Series',
        seriesIndex: 7,
      );
      final patched = writer.patchBytes(zipBytes, newMeta, isZip: true);
      final reparsed = parser.parseBytes(patched, isZip: true);
      expect(reparsed.title, 'Zipped New');
      expect(reparsed.author, 'Zip Author');
      expect(reparsed.series, 'Zip Series');
      expect(reparsed.seriesIndex, 7);
    });
  });
}

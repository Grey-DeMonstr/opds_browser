import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:opds_browser/domain/local_library.dart';

class Fb2MetadataParser {
  LocalBookMetadata parseBytes(Uint8List bytes, {bool isZip = false}) {
    final xmlBytes = isZip ? _extractFb2FromZip(bytes) : bytes;
    final xmlString = utf8.decode(xmlBytes, allowMalformed: true);
    return parseXml(xmlString);
  }

  Uint8List _extractFb2FromZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files
        .where((f) => f.isFile)
        .firstWhere(
          (f) => f.name.toLowerCase().endsWith('.fb2'),
          orElse: () => throw FormatException('No .fb2 file found in zip'),
        );
    return entry.content as Uint8List;
  }

  LocalBookMetadata parseXml(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlParserException catch (e) {
      throw FormatException('Invalid FB2 XML: $e');
    }

    final titleInfo = doc.findAllElements('title-info').firstOrNull;
    if (titleInfo == null) {
      throw FormatException('No title-info element in FB2');
    }

    final title =
        titleInfo.findElements('book-title').firstOrNull?.innerText.trim() ??
        '';

    final authorStrings = titleInfo
        .findElements('author')
        .map((authorEl) {
          final parts = ['first-name', 'middle-name', 'last-name']
              .map(
                (tag) =>
                    authorEl.findElements(tag).firstOrNull?.innerText.trim() ??
                    '',
              )
              .where((s) => s.isNotEmpty)
              .toList();
          return parts.join(' ');
        })
        .where((s) => s.isNotEmpty)
        .toList();
    final author = authorStrings.join(', ');

    final sequence = titleInfo.findElements('sequence').firstOrNull;
    final series = sequence?.getAttribute('name')?.trim();
    final seriesIndexStr = sequence?.getAttribute('number')?.trim();
    final seriesIndex = seriesIndexStr != null && seriesIndexStr.isNotEmpty
        ? int.tryParse(seriesIndexStr)
        : null;

    return LocalBookMetadata(
      title: title,
      author: author,
      series: series != null && series.isNotEmpty ? series : null,
      seriesIndex: seriesIndex,
    );
  }
}

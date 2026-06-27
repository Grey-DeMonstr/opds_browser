import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:opds_browser/domain/local_library.dart';

class Fb2MetadataWriter {
  Uint8List patchBytes(
    Uint8List bytes,
    LocalBookMetadata meta, {
    bool isZip = false,
  }) {
    if (isZip) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();
      for (final file in archive.files) {
        if (file.isFile && file.name.toLowerCase().endsWith('.fb2')) {
          final xmlBytes = file.content as List<int>;
          final patched = _patchXmlBytes(
            xmlBytes is Uint8List ? xmlBytes : Uint8List.fromList(xmlBytes),
            meta,
          );
          newArchive.addFile(ArchiveFile(file.name, patched.length, patched));
        } else {
          newArchive.addFile(file);
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
    }
    return _patchXmlBytes(bytes, meta);
  }

  Uint8List _patchXmlBytes(Uint8List bytes, LocalBookMetadata meta) {
    final xml = utf8.decode(bytes, allowMalformed: true);
    return Uint8List.fromList(utf8.encode(patchXml(xml, meta)));
  }

  String patchXml(String xml, LocalBookMetadata meta) {
    final doc = XmlDocument.parse(xml);
    final titleInfo = doc.findAllElements('title-info').firstOrNull;
    if (titleInfo == null) throw FormatException('No title-info element');

    _updateAuthors(titleInfo, meta.author);
    _updateBookTitle(titleInfo, meta.title);
    _updateSequence(titleInfo, meta.series, meta.seriesIndex);

    return doc.toXmlString(pretty: false);
  }

  void _updateAuthors(XmlElement titleInfo, String author) {
    // Remove all existing <author> elements
    for (final el in titleInfo.findElements('author').toList()) {
      el.parent!.children.remove(el);
    }
    // Build new <author><last-name>...</last-name></author>
    final authorEl = XmlElement(const XmlName.parts('author'), [], [
      XmlElement(const XmlName.parts('last-name'), [], [XmlText(author)]),
    ]);
    // Insert before <book-title> if present, otherwise append
    final bookTitle = titleInfo.findElements('book-title').firstOrNull;
    if (bookTitle != null) {
      final idx = titleInfo.children.indexOf(bookTitle);
      titleInfo.children.insert(idx, authorEl);
    } else {
      titleInfo.children.add(authorEl);
    }
  }

  void _updateBookTitle(XmlElement titleInfo, String title) {
    final bookTitle = titleInfo.findElements('book-title').firstOrNull;
    if (bookTitle != null) {
      bookTitle.children.clear();
      bookTitle.children.add(XmlText(title));
    } else {
      titleInfo.children.add(
        XmlElement(const XmlName.parts('book-title'), [], [XmlText(title)]),
      );
    }
  }

  void _updateSequence(XmlElement titleInfo, String? series, int? seriesIndex) {
    // Remove any existing <sequence> elements
    for (final el in titleInfo.findElements('sequence').toList()) {
      el.parent!.children.remove(el);
    }
    if (series != null) {
      final attrs = <XmlAttribute>[
        XmlAttribute(const XmlName.parts('name'), series),
      ];
      if (seriesIndex != null) {
        attrs.add(
          XmlAttribute(const XmlName.parts('number'), seriesIndex.toString()),
        );
      }
      titleInfo.children.add(
        XmlElement(const XmlName.parts('sequence'), attrs),
      );
    }
  }
}

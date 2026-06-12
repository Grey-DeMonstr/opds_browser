import 'dart:convert';

import 'package:opds_browser/data/opds_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';

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

/// Strips HTML tags and collapses whitespace to single spaces.
String stripHtml(String input) => input
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Resolves [href] against [base] following RFC 3986.
Uri resolveHref(String href, Uri base) => base.resolve(href);

class Opds1FeedParser implements OpdsFeedParser {
  @override
  ParsedFeed parse(List<int> bytes, Uri feedUrl) =>
      throw UnimplementedError('parse not yet implemented');
}

# Local Library — Plan 02: FB2 Data Layer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add archive dependency, define the domain model for the local library, implement the FB2 metadata parser, writer, and SQLite cache.

**Architecture:** Pure Dart in `domain/` and `data/`. `Fb2MetadataParser` and `Fb2MetadataWriter` operate on in-memory `Uint8List`/`String`. `SqfliteLocalLibraryCache` adds a new table to the existing `AppDatabase` via a v2 migration.

**Tech Stack:** `xml` (already in project), `archive ^3.6.0` (new), `sqflite_common_ffi` for tests.

## Global Constraints

- Android only — no iOS-specific code.
- Pure Dart in `domain/` and `data/` — no Flutter imports.
- `dart run tool/check.dart` must be clean after every task.
- Commit after every task.

## Prerequisite

Plan 01 must be complete (`SystemDownloads` removed, `AppSettings.target` is `CustomSafFolder?`).

---

## File Map

| File | Action |
|------|--------|
| `pubspec.yaml` | add `archive` |
| `lib/domain/local_library.dart` | new — domain types and interfaces |
| `lib/data/fb2_metadata_parser.dart` | new |
| `lib/data/fb2_metadata_writer.dart` | new |
| `lib/data/app_database.dart` | modify — v2 migration |
| `lib/data/sqflite_local_library_cache.dart` | new |
| `test/data/fb2_metadata_parser_test.dart` | new |
| `test/data/fb2_metadata_writer_test.dart` | new |
| `test/data/sqflite_local_library_cache_test.dart` | new |
| `test/data/app_database_test.dart` | modify — add v2 table check |

---

### Task 1: Add `archive` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add archive to `pubspec.yaml` dependencies**

```yaml
dependencies:
  archive: ^3.6.0
  # ... existing dependencies unchanged
```

- [ ] **Step 2: Run `flutter pub get`**

```powershell
flutter pub get
```

- [ ] **Step 3: Commit**

```powershell
git add pubspec.yaml pubspec.lock
git commit -m "chore: add archive dependency for fb2.zip support"
```

---

### Task 2: Domain model — `LocalBookMetadata`, `LibraryNode` tree, `LocalLibraryScanner`, `LocalBookReadWriter`

**Files:**
- Create: `lib/domain/local_library.dart`

**Interfaces produced:**
```dart
class LocalBookMetadata { String title; String author; String? series; int? seriesIndex; }
sealed class LibraryNode {}
class LibraryFolder extends LibraryNode { String name; List<LibraryNode> children; bool hasWarning; }
class LibraryBook   extends LibraryNode { String relativePath; String documentUri; String parentUri; LocalBookMetadata meta; bool isInvalid; }
class LibraryFile   { String relativePath; String documentUri; String parentUri; }
abstract interface class LocalLibraryScanner { Stream<LibraryFile> scan(String treeUri); }
abstract interface class LocalBookReadWriter {
  Future<Uint8List> readBytes(String documentUri);
  Future<void> writeBytes(String documentUri, String parentUri, String fileName, String mimeType, Uint8List bytes);
}
```

- [ ] **Step 1: Create `lib/domain/local_library.dart`**

```dart
import 'dart:typed_data';

class LocalBookMetadata {
  const LocalBookMetadata({
    required this.title,
    required this.author,
    this.series,
    this.seriesIndex,
  });

  final String title;
  final String author;
  final String? series;
  final int? seriesIndex;

  LocalBookMetadata copyWith({
    String? title,
    String? author,
    String? series,
    int? seriesIndex,
    bool clearSeries = false,
    bool clearSeriesIndex = false,
  }) => LocalBookMetadata(
    title: title ?? this.title,
    author: author ?? this.author,
    series: clearSeries ? null : (series ?? this.series),
    seriesIndex: clearSeriesIndex ? null : (seriesIndex ?? this.seriesIndex),
  );
}

class LibraryFile {
  const LibraryFile({
    required this.relativePath,
    required this.documentUri,
    required this.parentUri,
  });

  final String relativePath; // e.g. "Jane Doe/Series/book.fb2"
  final String documentUri;  // SAF document URI for reading
  final String parentUri;    // SAF directory URI for writing
}

sealed class LibraryNode {}

class LibraryFolder extends LibraryNode {
  LibraryFolder({
    required this.name,
    required this.children,
    this.hasWarning = false,
  });

  final String name;
  final List<LibraryNode> children;
  final bool hasWarning;

  LibraryFolder copyWith({List<LibraryNode>? children, bool? hasWarning}) =>
      LibraryFolder(
        name: name,
        children: children ?? this.children,
        hasWarning: hasWarning ?? this.hasWarning,
      );
}

class LibraryBook extends LibraryNode {
  LibraryBook({
    required this.relativePath,
    required this.documentUri,
    required this.parentUri,
    required this.meta,
    this.isInvalid = false,
  });

  final String relativePath;
  final String documentUri;
  final String parentUri;
  final LocalBookMetadata meta;
  final bool isInvalid;

  LibraryBook copyWith({LocalBookMetadata? meta, bool? isInvalid}) =>
      LibraryBook(
        relativePath: relativePath,
        documentUri: documentUri,
        parentUri: parentUri,
        meta: meta ?? this.meta,
        isInvalid: isInvalid ?? this.isInvalid,
      );
}

abstract interface class LocalLibraryScanner {
  Stream<LibraryFile> scan(String treeUri);
}

abstract interface class LocalBookReadWriter {
  Future<Uint8List> readBytes(String documentUri);

  /// Overwrites the existing file identified by [documentUri].
  /// [parentUri] and [fileName] identify the location for write-back.
  /// [mimeType] is 'application/x-fictionbook+xml' for .fb2,
  /// 'application/zip' for .fb2.zip.
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  );
}
```

- [ ] **Step 2: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 3: Commit**

```powershell
git add lib/domain/local_library.dart
git commit -m "feat: add local library domain model and interfaces"
```

---

### Task 3: `Fb2MetadataParser`

**Files:**
- Create: `lib/data/fb2_metadata_parser.dart`
- Create: `test/data/fb2_metadata_parser_test.dart`

FB2 XML structure (relevant portion):
```xml
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
  <description>
    <title-info>
      <author><first-name>Jane</first-name><middle-name>M</middle-name><last-name>Doe</last-name></author>
      <author><first-name>John</first-name><last-name>Smith</last-name></author>
      <book-title>My Book</book-title>
      <sequence name="My Series" number="3"/>
    </title-info>
  </description>
  <body>...</body>
</FictionBook>
```

- [ ] **Step 1: Write the failing tests**

Create `test/data/fb2_metadata_parser_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/fb2_metadata_parser.dart';
import 'package:opds_browser/domain/local_library.dart';

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
      expect(() => parser.parseXml('<not valid xml>>>'), throwsA(isA<FormatException>()));
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
```

- [ ] **Step 2: Run test — expect FAIL**

```powershell
flutter test test/data/fb2_metadata_parser_test.dart
```

- [ ] **Step 3: Create `lib/data/fb2_metadata_parser.dart`**

```dart
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
    final entry = archive.files.where((f) => f.isFile).firstWhere(
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
    if (titleInfo == null) throw FormatException('No title-info element in FB2');

    final title = titleInfo.findElements('book-title').firstOrNull?.innerText.trim() ?? '';

    final authorStrings = titleInfo.findElements('author').map((authorEl) {
      final parts = ['first-name', 'middle-name', 'last-name']
          .map((tag) => authorEl.findElements(tag).firstOrNull?.innerText.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return parts.join(' ');
    }).where((s) => s.isNotEmpty).toList();
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
```

- [ ] **Step 4: Run test — expect PASS**

```powershell
flutter test test/data/fb2_metadata_parser_test.dart
```

- [ ] **Step 5: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 6: Commit**

```powershell
git add lib/data/fb2_metadata_parser.dart test/data/fb2_metadata_parser_test.dart
git commit -m "feat: add Fb2MetadataParser with fb2.zip support"
```

---

### Task 4: `Fb2MetadataWriter`

**Files:**
- Create: `lib/data/fb2_metadata_writer.dart`
- Create: `test/data/fb2_metadata_writer_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/data/fb2_metadata_writer_test.dart`:

```dart
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
      const newMeta = LocalBookMetadata(title: 'New Title', author: 'Jane Doe', series: 'Old Series', seriesIndex: 2);
      final patched = writer.patchXml(_baseXml, newMeta);
      final reparsed = parser.parseXml(patched);
      expect(reparsed.title, 'New Title');
    });

    test('round-trip: author updated as single last-name field', () {
      const newMeta = LocalBookMetadata(title: 'Old Title', author: 'John Smith', series: 'Old Series', seriesIndex: 2);
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
      const newMeta = LocalBookMetadata(title: 'Old Title', author: 'Jane Doe', series: 'New Series', seriesIndex: 5);
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
      const newMeta = LocalBookMetadata(title: 'No Series Book', author: 'Smith', series: 'Added Series', seriesIndex: 1);
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
      const newMeta = LocalBookMetadata(title: 'Zipped New', author: 'Zip Author', series: 'Zip Series', seriesIndex: 7);
      final patched = writer.patchBytes(zipBytes, newMeta, isZip: true);
      final reparsed = parser.parseBytes(patched, isZip: true);
      expect(reparsed.title, 'Zipped New');
      expect(reparsed.author, 'Zip Author');
      expect(reparsed.series, 'Zip Series');
      expect(reparsed.seriesIndex, 7);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

```powershell
flutter test test/data/fb2_metadata_writer_test.dart
```

- [ ] **Step 3: Create `lib/data/fb2_metadata_writer.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:opds_browser/domain/local_library.dart';

class Fb2MetadataWriter {
  Uint8List patchBytes(Uint8List bytes, LocalBookMetadata meta, {bool isZip = false}) {
    if (isZip) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();
      for (final file in archive.files) {
        if (file.isFile && file.name.toLowerCase().endsWith('.fb2')) {
          final xmlBytes = file.content as Uint8List;
          final patched = _patchXmlBytes(xmlBytes, meta);
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
    return utf8.encode(patchXml(xml, meta));
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
    // Remove existing author elements
    for (final el in titleInfo.findElements('author').toList()) {
      el.parent!.children.remove(el);
    }
    // Insert new author element before <book-title> (or at start)
    final authorEl = XmlElement(XmlName('author'), [], [
      XmlElement(XmlName('last-name'), [], [XmlText(author)]),
    ]);
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
        XmlElement(XmlName('book-title'), [], [XmlText(title)]),
      );
    }
  }

  void _updateSequence(XmlElement titleInfo, String? series, int? seriesIndex) {
    for (final el in titleInfo.findElements('sequence').toList()) {
      el.parent!.children.remove(el);
    }
    if (series != null) {
      final attrs = <XmlAttribute>[XmlAttribute(XmlName('name'), series)];
      if (seriesIndex != null) {
        attrs.add(XmlAttribute(XmlName('number'), seriesIndex.toString()));
      }
      titleInfo.children.add(XmlElement(XmlName('sequence'), attrs));
    }
  }
}
```

- [ ] **Step 4: Run test — expect PASS**

```powershell
flutter test test/data/fb2_metadata_writer_test.dart
```

- [ ] **Step 5: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 6: Commit**

```powershell
git add lib/data/fb2_metadata_writer.dart test/data/fb2_metadata_writer_test.dart
git commit -m "feat: add Fb2MetadataWriter with fb2.zip round-trip support"
```

---

### Task 5: SQLite cache + DB v2 migration

**Files:**
- Modify: `lib/data/app_database.dart`
- Create: `lib/data/sqflite_local_library_cache.dart`
- Create: `test/data/sqflite_local_library_cache_test.dart`
- Modify: `test/data/app_database_test.dart`

- [ ] **Step 1: Write the failing cache tests**

Create `test/data/sqflite_local_library_cache_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
import 'package:opds_browser/domain/local_library.dart';

AppDatabase _makeDb() =>
    AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

const _meta1 = LocalBookMetadata(title: 'Book One', author: 'Jane Doe', series: 'My Series', seriesIndex: 1);
const _meta2 = LocalBookMetadata(title: 'Book Two', author: 'John Smith');

void main() {
  late AppDatabase db;
  late SqfliteLocalLibraryCache cache;

  setUp(() {
    db = _makeDb();
    cache = SqfliteLocalLibraryCache(db);
  });
  tearDown(() => db.close());

  test('get returns null on cache miss', () async {
    expect(await cache.get('a/b.fb2'), isNull);
  });

  test('put then get returns stored metadata', () async {
    await cache.put('a/b.fb2', _meta1);
    final result = await cache.get('a/b.fb2');
    expect(result?.title, 'Book One');
    expect(result?.author, 'Jane Doe');
    expect(result?.series, 'My Series');
    expect(result?.seriesIndex, 1);
  });

  test('put overwrites existing entry', () async {
    await cache.put('a/b.fb2', _meta1);
    await cache.put('a/b.fb2', _meta2);
    final result = await cache.get('a/b.fb2');
    expect(result?.title, 'Book Two');
    expect(result?.series, isNull);
    expect(result?.seriesIndex, isNull);
  });

  test('putAll stores multiple entries', () async {
    await cache.putAll({'a/1.fb2': _meta1, 'b/2.fb2': _meta2});
    expect((await cache.get('a/1.fb2'))?.title, 'Book One');
    expect((await cache.get('b/2.fb2'))?.title, 'Book Two');
  });

  test('deleteAll empties the table', () async {
    await cache.putAll({'a/1.fb2': _meta1, 'b/2.fb2': _meta2});
    await cache.deleteAll();
    expect(await cache.get('a/1.fb2'), isNull);
    expect(await cache.get('b/2.fb2'), isNull);
  });

  test('null series_index round-trips as null', () async {
    await cache.put('c/d.fb2', _meta2);
    final result = await cache.get('c/d.fb2');
    expect(result?.seriesIndex, isNull);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

```powershell
flutter test test/data/sqflite_local_library_cache_test.dart
```

- [ ] **Step 3: Update `lib/data/app_database.dart` — add v2 migration**

Replace the file with:

```dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  final DatabaseFactory _factory;
  final String? _path;
  Database? _db;

  // ignore: prefer_initializing_formals
  AppDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory ?? databaseFactory,
      // ignore: prefer_initializing_formals
      _path = path;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = _path ?? join(await getDatabasesPath(), 'opds_browser.db');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await _createV1Schema(db);
          await _createV2Schema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createV2Schema(db);
        },
      ),
    );
  }

  Future<void> _createV1Schema(Database db) async {
    await db.execute('''
      CREATE TABLE catalogs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT    NOT NULL,
        root_url   TEXT    NOT NULL,
        protocol   TEXT    NOT NULL DEFAULT 'opds1',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE feed_cache (
        catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
        url        TEXT    NOT NULL,
        feed_json  TEXT    NOT NULL,
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (catalog_id, url)
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        catalog_id INTEGER NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
        url        TEXT    NOT NULL,
        title      TEXT    NOT NULL,
        sort_order INTEGER NOT NULL,
        UNIQUE (catalog_id, url)
      )
    ''');
  }

  Future<void> _createV2Schema(Database db) async {
    await db.execute('''
      CREATE TABLE local_book_cache (
        path         TEXT    PRIMARY KEY,
        title        TEXT    NOT NULL,
        author       TEXT    NOT NULL,
        series       TEXT,
        series_index INTEGER
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
```

- [ ] **Step 4: Create `lib/data/sqflite_local_library_cache.dart`**

```dart
import 'package:sqflite/sqflite.dart';
import 'package:opds_browser/data/app_database.dart';
import 'package:opds_browser/domain/local_library.dart';

class SqfliteLocalLibraryCache {
  final AppDatabase _db;
  SqfliteLocalLibraryCache(this._db);

  Future<LocalBookMetadata?> get(String path) async {
    final db = await _db.database;
    final rows = await db.query(
      'local_book_cache',
      where: 'path = ?',
      whereArgs: [path],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> put(String path, LocalBookMetadata meta) async {
    final db = await _db.database;
    await db.insert(
      'local_book_cache',
      _toRow(path, meta),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putAll(Map<String, LocalBookMetadata> entries) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final e in entries.entries) {
        await txn.insert(
          'local_book_cache',
          _toRow(e.key, e.value),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteAll() async {
    final db = await _db.database;
    await db.delete('local_book_cache');
  }

  Map<String, Object?> _toRow(String path, LocalBookMetadata meta) => {
    'path': path,
    'title': meta.title,
    'author': meta.author,
    'series': meta.series,
    'series_index': meta.seriesIndex,
  };

  LocalBookMetadata _fromRow(Map<String, Object?> row) => LocalBookMetadata(
    title: row['title'] as String,
    author: row['author'] as String,
    series: row['series'] as String?,
    seriesIndex: row['series_index'] as int?,
  );
}
```

- [ ] **Step 5: Run cache test — expect PASS**

```powershell
flutter test test/data/sqflite_local_library_cache_test.dart
```

- [ ] **Step 6: Add `local_book_cache` table assertion to `test/data/app_database_test.dart`**

Add this test inside the `'AppDatabase schema'` group:

```dart
test('local_book_cache table exists after open', () async {
  final d = await db.database;
  final names = (await tables(d)).map((r) => r['name']).toList();
  expect(names, contains('local_book_cache'));
});
```

- [ ] **Step 7: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 8: Commit**

```powershell
git add lib/data/app_database.dart lib/data/sqflite_local_library_cache.dart test/data/sqflite_local_library_cache_test.dart test/data/app_database_test.dart
git commit -m "feat: add SQLite local book cache (v2 DB migration)"
```

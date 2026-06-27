import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/fb2_metadata_writer.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';

// A minimal valid FB2 XML for round-trip testing
const _minimalFb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook>
  <description>
    <title-info>
      <author><last-name>Old Author</last-name></author>
      <book-title>Old Title</book-title>
    </title-info>
  </description>
  <body><section><p>.</p></section></body>
</FictionBook>''';

class _FakeReadWriter implements LocalBookReadWriter {
  final _writtenUris = <String>[];
  List<String> get writtenUris => _writtenUris;

  @override
  Future<Uint8List> readBytes(String documentUri) async =>
      Uint8List.fromList(_minimalFb2.codeUnits);

  @override
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    _writtenUris.add(documentUri);
  }
}

LibraryBook _invalidBook(String relativePath, LocalBookMetadata meta) =>
    LibraryBook(
      relativePath: relativePath,
      documentUri: 'content://doc/${relativePath.hashCode}',
      parentUri: 'content://parent',
      meta: meta,
      isInvalid: true,
    );

LibraryFolder _folder(String name, List<LibraryNode> children) =>
    LibraryFolder(name: name, children: children, hasWarning: true);

void main() {
  sqfliteFfiInit();

  group('LocalLibraryFixer', () {
    late _FakeReadWriter rw;
    late SqfliteLocalLibraryCache cache;
    late Fb2MetadataWriter writer;
    late LocalLibraryFixer fixer;

    setUp(() async {
      rw = _FakeReadWriter();
      writer = Fb2MetadataWriter();
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      cache = SqfliteLocalLibraryCache(db);
      fixer = LocalLibraryFixer(readWriter: rw, writer: writer, cache: cache);
    });

    test('depth 0 — skips book in library root', () async {
      const meta = LocalBookMetadata(title: 'T', author: 'Wrong');
      final root = _folder('root', [_invalidBook('book.fb2', meta)]);

      final (result, _) = await fixer.fix(root);

      expect(rw.writtenUris, isEmpty);
      expect(result.fixed, 0);
      expect(result.skipped, 1);
    });

    test('depth 1 — sets author from folder, clears series', () async {
      const meta = LocalBookMetadata(
        title: 'T',
        author: 'Wrong',
        series: 'Old Series',
        seriesIndex: 3,
      );
      final root = _folder('root', [
        _folder('Jane Doe', [_invalidBook('Jane Doe/book.fb2', meta)]),
      ]);

      final (result, newRoot) = await fixer.fix(root);

      expect(result.fixed, 1);
      expect(result.skipped, 0);
      expect(rw.writtenUris, hasLength(1));

      // In-memory tree updated
      final book = newRoot.children
          .whereType<LibraryFolder>()
          .first
          .children
          .whereType<LibraryBook>()
          .first;
      expect(book.meta.author, 'Jane Doe');
      expect(book.meta.series, isNull);
      expect(book.meta.seriesIndex, isNull);

      // Cache updated
      final cached = await cache.get('Jane Doe/book.fb2');
      expect(cached?.author, 'Jane Doe');
      expect(cached?.series, isNull);
    });

    test('depth 2 — sets author and series, preserves seriesIndex', () async {
      const meta = LocalBookMetadata(
        title: 'T',
        author: 'Wrong',
        seriesIndex: 5,
      );
      final root = _folder('root', [
        _folder('Jane Doe', [
          _folder('Jane Doe/My Series', [
            _invalidBook('Jane Doe/My Series/book.fb2', meta),
          ]),
        ]),
      ]);

      final (result, newRoot) = await fixer.fix(root);

      expect(result.fixed, 1);
      expect(result.skipped, 0);

      final book = newRoot.children
          .whereType<LibraryFolder>()
          .first
          .children
          .whereType<LibraryFolder>()
          .first
          .children
          .whereType<LibraryBook>()
          .first;
      expect(book.meta.author, 'Jane Doe');
      expect(book.meta.series, 'My Series');
      expect(book.meta.seriesIndex, 5);
    });

    test('depth > 2 — skips', () async {
      const meta = LocalBookMetadata(title: 'T', author: 'Wrong');
      final root = _folder('root', [
        _folder('A', [
          _folder('A/B', [
            _folder('A/B/C', [_invalidBook('A/B/C/book.fb2', meta)]),
          ]),
        ]),
      ]);

      final (result, _) = await fixer.fix(root);

      expect(rw.writtenUris, isEmpty);
      expect(result.fixed, 0);
      expect(result.skipped, 1);
    });

    test('only calls writer for invalid books', () async {
      const validMeta = LocalBookMetadata(title: 'T', author: 'Jane Doe');
      const invalidMeta = LocalBookMetadata(title: 'T', author: 'Wrong');
      final root = _folder('root', [
        _folder('Jane Doe', [
          LibraryBook(
            relativePath: 'Jane Doe/valid.fb2',
            documentUri: 'content://doc/v',
            parentUri: 'content://parent',
            meta: validMeta,
            isInvalid: false,
          ),
          _invalidBook('Jane Doe/invalid.fb2', invalidMeta),
        ]),
      ]);

      final (result, _) = await fixer.fix(root);

      expect(rw.writtenUris, hasLength(1));
      expect(result.fixed, 1);
      expect(result.skipped, 0);
    });
  });
}

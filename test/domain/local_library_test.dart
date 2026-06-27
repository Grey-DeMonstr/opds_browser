import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/local_library.dart';

void main() {
  group('LocalBookMetadata', () {
    test('stores all fields', () {
      const meta = LocalBookMetadata(
        title: 'Test Book',
        author: 'Test Author',
        series: 'Test Series',
        seriesIndex: 1,
      );
      expect(meta.title, 'Test Book');
      expect(meta.author, 'Test Author');
      expect(meta.series, 'Test Series');
      expect(meta.seriesIndex, 1);
    });

    test('series and seriesIndex are optional', () {
      const meta = LocalBookMetadata(title: 'Test Book', author: 'Test Author');
      expect(meta.title, 'Test Book');
      expect(meta.author, 'Test Author');
      expect(meta.series, isNull);
      expect(meta.seriesIndex, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const original = LocalBookMetadata(
        title: 'Original',
        author: 'Author',
        series: 'Series',
        seriesIndex: 1,
      );
      final updated = original.copyWith(title: 'Updated');
      expect(updated.title, 'Updated');
      expect(updated.author, 'Author');
      expect(updated.series, 'Series');
      expect(updated.seriesIndex, 1);
    });

    test('copyWith can clear series', () {
      const original = LocalBookMetadata(
        title: 'Test',
        author: 'Author',
        series: 'Series',
      );
      final updated = original.copyWith(clearSeries: true);
      expect(updated.series, isNull);
      expect(updated.title, 'Test');
    });

    test('copyWith can clear seriesIndex', () {
      const original = LocalBookMetadata(
        title: 'Test',
        author: 'Author',
        seriesIndex: 5,
      );
      final updated = original.copyWith(clearSeriesIndex: true);
      expect(updated.seriesIndex, isNull);
      expect(updated.title, 'Test');
    });

    test('copyWith can update series and seriesIndex together', () {
      const original = LocalBookMetadata(
        title: 'Test',
        author: 'Author',
        series: 'Old Series',
        seriesIndex: 1,
      );
      final updated = original.copyWith(series: 'New Series', seriesIndex: 2);
      expect(updated.series, 'New Series');
      expect(updated.seriesIndex, 2);
    });
  });

  group('LibraryFile', () {
    test('stores all fields', () {
      const file = LibraryFile(
        relativePath: 'Jane Doe/Series/book.fb2',
        documentUri: 'content://com.example/document/123',
        parentUri: 'content://com.example/tree/456',
      );
      expect(file.relativePath, 'Jane Doe/Series/book.fb2');
      expect(file.documentUri, 'content://com.example/document/123');
      expect(file.parentUri, 'content://com.example/tree/456');
    });
  });

  group('LibraryFolder', () {
    test('stores all fields', () {
      final folder = LibraryFolder(
        name: 'My Folder',
        children: const [],
        hasWarning: false,
      );
      expect(folder.name, 'My Folder');
      expect(folder.children, isEmpty);
      expect(folder.hasWarning, isFalse);
    });

    test('hasWarning defaults to false', () {
      final folder = LibraryFolder(name: 'My Folder', children: const []);
      expect(folder.hasWarning, isFalse);
    });

    test('can contain nested LibraryNodes', () {
      final book = LibraryBook(
        relativePath: 'book.fb2',
        documentUri: 'uri1',
        parentUri: 'uri2',
        meta: const LocalBookMetadata(title: 'Title', author: 'Author'),
      );
      final folder = LibraryFolder(name: 'Folder', children: [book]);
      expect(folder.children.length, 1);
      expect(folder.children.first, isA<LibraryBook>());
    });

    test('copyWith preserves name and updates children', () {
      final originalBook = LibraryBook(
        relativePath: 'book.fb2',
        documentUri: 'uri1',
        parentUri: 'uri2',
        meta: const LocalBookMetadata(title: 'Title', author: 'Author'),
      );
      final originalFolder = LibraryFolder(
        name: 'Folder',
        children: [originalBook],
      );
      final updatedFolder = originalFolder.copyWith(children: const []);
      expect(updatedFolder.name, 'Folder');
      expect(updatedFolder.children, isEmpty);
    });

    test('copyWith can update hasWarning', () {
      final folder = LibraryFolder(
        name: 'Folder',
        children: const [],
        hasWarning: false,
      );
      final updated = folder.copyWith(hasWarning: true);
      expect(updated.name, 'Folder');
      expect(updated.hasWarning, isTrue);
    });
  });

  group('LibraryBook', () {
    test('stores all fields', () {
      const meta = LocalBookMetadata(title: 'Test Book', author: 'Test Author');
      final book = LibraryBook(
        relativePath: 'path/to/book.fb2',
        documentUri: 'content://doc/123',
        parentUri: 'content://tree/456',
        meta: meta,
        isInvalid: false,
      );
      expect(book.relativePath, 'path/to/book.fb2');
      expect(book.documentUri, 'content://doc/123');
      expect(book.parentUri, 'content://tree/456');
      expect(book.meta.title, 'Test Book');
      expect(book.isInvalid, isFalse);
    });

    test('isInvalid defaults to false', () {
      const meta = LocalBookMetadata(title: 'Title', author: 'Author');
      final book = LibraryBook(
        relativePath: 'book.fb2',
        documentUri: 'uri1',
        parentUri: 'uri2',
        meta: meta,
      );
      expect(book.isInvalid, isFalse);
    });

    test('copyWith preserves immutable fields and updates mutable ones', () {
      const originalMeta = LocalBookMetadata(
        title: 'Original',
        author: 'Author',
      );
      final originalBook = LibraryBook(
        relativePath: 'book.fb2',
        documentUri: 'uri1',
        parentUri: 'uri2',
        meta: originalMeta,
        isInvalid: false,
      );
      const newMeta = LocalBookMetadata(title: 'Updated', author: 'Author');
      final updatedBook = originalBook.copyWith(meta: newMeta);
      expect(updatedBook.relativePath, 'book.fb2');
      expect(updatedBook.documentUri, 'uri1');
      expect(updatedBook.parentUri, 'uri2');
      expect(updatedBook.meta.title, 'Updated');
      expect(updatedBook.isInvalid, isFalse);
    });

    test('copyWith can update isInvalid', () {
      const meta = LocalBookMetadata(title: 'Title', author: 'Author');
      final originalBook = LibraryBook(
        relativePath: 'book.fb2',
        documentUri: 'uri1',
        parentUri: 'uri2',
        meta: meta,
        isInvalid: false,
      );
      final updatedBook = originalBook.copyWith(isInvalid: true);
      expect(updatedBook.relativePath, 'book.fb2');
      expect(updatedBook.isInvalid, isTrue);
    });
  });

  group('LibraryNode', () {
    test('LibraryFolder is a LibraryNode', () {
      final folder = LibraryFolder(name: 'Folder', children: const []);
      expect(folder, isA<LibraryNode>());
    });

    test('LibraryBook is a LibraryNode', () {
      const meta = LocalBookMetadata(title: 'Title', author: 'Author');
      final book = LibraryBook(
        relativePath: 'book.fb2',
        documentUri: 'uri1',
        parentUri: 'uri2',
        meta: meta,
      );
      expect(book, isA<LibraryNode>());
    });
  });

  group('LocalLibraryScanner', () {
    test('is an abstract interface', () {
      // This test verifies the interface is properly defined
      // We can't instantiate it directly, but we can check that
      // the signature matches expectations via a mock or implementation
      expect(const LocalLibraryScannerMock(), isA<LocalLibraryScanner>());
    });
  });

  group('LocalBookReadWriter', () {
    test('is an abstract interface', () {
      // This test verifies the interface is properly defined
      expect(const LocalBookReadWriterMock(), isA<LocalBookReadWriter>());
    });
  });
}

// Mock implementations for interface tests
class LocalLibraryScannerMock implements LocalLibraryScanner {
  const LocalLibraryScannerMock();

  @override
  Stream<LibraryFile> scan(String treeUri) async* {
    // Not used in test
  }
}

class LocalBookReadWriterMock implements LocalBookReadWriter {
  const LocalBookReadWriterMock();

  @override
  Future<Uint8List> readBytes(String documentUri) async {
    return Uint8List(0);
  }

  @override
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    // Not used in test
  }
}

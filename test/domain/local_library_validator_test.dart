import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/local_library.dart';

LibraryBook _book(String relativePath, LocalBookMetadata meta) => LibraryBook(
  relativePath: relativePath,
  documentUri: 'content://fake/$relativePath',
  parentUri: 'content://fake/parent',
  meta: meta,
  isInvalid: false,
);

LibraryFolder _folder(String name, List<LibraryNode> children) =>
    LibraryFolder(name: name, children: children, hasWarning: false);

const _validator = LocalLibraryValidator();

void main() {
  group('LocalLibraryValidator', () {
    group('depth 0 — book in root', () {
      test('always invalid', () {
        const meta = LocalBookMetadata(title: 'T', author: 'Jane Doe');
        final root = _folder('root', [_book('book.fb2', meta)]);
        final result = _validator.validate(root);
        final book = result.children.whereType<LibraryBook>().first;
        expect(book.isInvalid, isTrue);
        expect(result.hasWarning, isTrue);
      });
    });

    group('depth 1', () {
      test('valid when no series and author name matches', () {
        const meta = LocalBookMetadata(title: 'T', author: 'Jane Doe');
        final root = _folder('root', [
          _folder('Jane Doe', [_book('Jane Doe/book.fb2', meta)]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isFalse);
        expect(result.hasWarning, isFalse);
      });

      test(
        'invalid when author name mismatches (case-sensitive char difference)',
        () {
          const meta = LocalBookMetadata(title: 'T', author: 'jane doe');
          // "Jane Doe" folder vs "jane doe" in meta
          final root = _folder('root', [
            _folder('Jane Doe', [_book('Jane Doe/book.fb2', meta)]),
          ]);
          final result = _validator.validate(root);
          // Case-insensitive: still valid
          final book = result.children
              .whereType<LibraryFolder>()
              .first
              .children
              .whereType<LibraryBook>()
              .first;
          expect(book.isInvalid, isFalse);
        },
      );

      test('invalid when author name truly mismatches', () {
        const meta = LocalBookMetadata(title: 'T', author: 'John Smith');
        final root = _folder('root', [
          _folder('Jane Doe', [_book('Jane Doe/book.fb2', meta)]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isTrue);
      });

      test('invalid when has series (wrong depth)', () {
        const meta = LocalBookMetadata(
          title: 'T',
          author: 'Jane Doe',
          series: 'My Series',
        );
        final root = _folder('root', [
          _folder('Jane Doe', [_book('Jane Doe/book.fb2', meta)]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isTrue);
      });
    });

    group('depth 2', () {
      test('valid when has series and both names match', () {
        const meta = LocalBookMetadata(
          title: 'T',
          author: 'Jane Doe',
          series: 'My Series',
        );
        final root = _folder('root', [
          _folder('Jane Doe', [
            _folder('Jane Doe/My Series', [
              _book('Jane Doe/My Series/book.fb2', meta),
            ]),
          ]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isFalse);
        expect(result.hasWarning, isFalse);
      });

      test('invalid when author mismatches', () {
        const meta = LocalBookMetadata(
          title: 'T',
          author: 'John Smith',
          series: 'My Series',
        );
        final root = _folder('root', [
          _folder('Jane Doe', [
            _folder('Jane Doe/My Series', [
              _book('Jane Doe/My Series/book.fb2', meta),
            ]),
          ]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isTrue);
      });

      test('invalid when series name mismatches', () {
        const meta = LocalBookMetadata(
          title: 'T',
          author: 'Jane Doe',
          series: 'Other Series',
        );
        final root = _folder('root', [
          _folder('Jane Doe', [
            _folder('Jane Doe/My Series', [
              _book('Jane Doe/My Series/book.fb2', meta),
            ]),
          ]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isTrue);
      });

      test('invalid when no series at depth 2', () {
        const meta = LocalBookMetadata(title: 'T', author: 'Jane Doe');
        final root = _folder('root', [
          _folder('Jane Doe', [
            _folder('Jane Doe/My Series', [
              _book('Jane Doe/My Series/book.fb2', meta),
            ]),
          ]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isTrue);
      });
    });

    group('depth > 2', () {
      test('always invalid', () {
        const meta = LocalBookMetadata(
          title: 'T',
          author: 'Jane Doe',
          series: 'S',
        );
        final root = _folder('root', [
          _folder('Jane Doe', [
            _folder('Jane Doe/S', [
              _folder('Jane Doe/S/Extra', [
                _book('Jane Doe/S/Extra/book.fb2', meta),
              ]),
            ]),
          ]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isTrue);
      });
    });

    group('case-insensitive and trim', () {
      test('leading/trailing whitespace is trimmed before comparison', () {
        const meta = LocalBookMetadata(title: 'T', author: '  Jane Doe  ');
        final root = _folder('root', [
          _folder('Jane Doe', [_book('Jane Doe/book.fb2', meta)]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isFalse);
      });

      test('comparison is case-insensitive', () {
        const meta = LocalBookMetadata(title: 'T', author: 'JANE DOE');
        final root = _folder('root', [
          _folder('jane doe', [_book('jane doe/book.fb2', meta)]),
        ]);
        final result = _validator.validate(root);
        final book = result.children
            .whereType<LibraryFolder>()
            .first
            .children
            .whereType<LibraryBook>()
            .first;
        expect(book.isInvalid, isFalse);
      });
    });

    group('hasWarning propagation', () {
      test('folder hasWarning is true when any descendant book is invalid', () {
        const valid = LocalBookMetadata(title: 'T', author: 'Jane Doe');
        const invalid = LocalBookMetadata(title: 'T', author: 'Wrong Author');
        final root = _folder('root', [
          _folder('Jane Doe', [
            _book('Jane Doe/book1.fb2', valid),
            _book('Jane Doe/book2.fb2', invalid),
          ]),
        ]);
        final result = _validator.validate(root);
        expect(result.hasWarning, isTrue);
        final folder = result.children.whereType<LibraryFolder>().first;
        expect(folder.hasWarning, isTrue);
      });

      test(
        'folder hasWarning is false when all descendant books are valid',
        () {
          const valid = LocalBookMetadata(title: 'T', author: 'Jane Doe');
          final root = _folder('root', [
            _folder('Jane Doe', [
              _book('Jane Doe/book1.fb2', valid),
              _book('Jane Doe/book2.fb2', valid),
            ]),
          ]);
          final result = _validator.validate(root);
          expect(result.hasWarning, isFalse);
        },
      );
    });
  });
}

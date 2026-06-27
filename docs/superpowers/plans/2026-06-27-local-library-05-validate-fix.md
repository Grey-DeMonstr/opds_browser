# Local Library — Plan 05: Validate and Fix (Steps 3 and 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Validate and Fix operations to the local library screen. Validate annotates each book in the tree with `isInvalid` (checked against folder structure + metadata name matching), propagates `hasWarning` up to folders, and re-emits `LibraryReady(validationRun: true)`. Fix rewrites metadata for all invalid depth-1 and depth-2 books from their folder names, then re-validates.

**Architecture:** Validate is a pure-function domain operation (`LocalLibraryValidator`) — no I/O, just walks the tree and returns an annotated copy. Fix is a domain orchestrator (`LocalLibraryFixer`) that calls `LocalBookReadWriter` + `Fb2MetadataWriter` + `SqfliteLocalLibraryCache` for each invalid book, then re-validates. Notifier wraps both in `validate()` and `fix()` async methods.

**Tech Stack:** `xml` (FB2), `archive` (fb2.zip, via Plan 02), `SqfliteLocalLibraryCache` (Plan 02), `LocalBookReadWriter` / `SafBookReadWriter` (Plans 03-04), Riverpod `Notifier`.

## Global Constraints

- Android only.
- `dart run tool/check.dart` must be clean after every task.
- Commit after every task.

## Prerequisites

- Plan 02 complete (`Fb2MetadataWriter`, `SqfliteLocalLibraryCache`)
- Plan 03 complete (`LocalLibraryNotifier`, `LocalLibraryScreen`, `LibraryReady` state)
- Plan 04 complete (`SafBookReadWriter.writeBytes`, `LocalLibraryNotifier.updateBook`)

---

## File Map

| File | Action |
|------|--------|
| `lib/domain/local_library.dart` | modify — add `LocalLibraryValidator` + `LocalLibraryFixer` |
| `lib/ui/local_library_screen.dart` | modify — add `validate()` + `fix()` to notifier; add AppBar buttons |
| `test/domain/local_library_validator_test.dart` | new |
| `test/domain/local_library_fixer_test.dart` | new |
| `test/ui/local_library_notifier_test.dart` | modify — add validate/fix flow tests |

---

### Task 1: `LocalLibraryValidator` — pure domain function

**Files:**
- Modify: `lib/domain/local_library.dart`
- Create: `test/domain/local_library_validator_test.dart`

**Validity rule** (recap from design spec):

```
segments = relativePath.split('/').dropLast(1)   // folder segments only
depth    = segments.length

depth 0 → invalid (book in library root)
depth 1 → valid IFF meta.series == null
            AND segments[0].toLowerCase().trim() == meta.author.toLowerCase().trim()
depth 2 → valid IFF meta.series != null
            AND segments[0].toLowerCase().trim() == meta.author.toLowerCase().trim()
            AND segments[1].toLowerCase().trim() == meta.series!.toLowerCase().trim()
depth > 2 → invalid
```

After per-book annotation, propagate `hasWarning` bottom-up: a `LibraryFolder` is `hasWarning` iff any descendant `LibraryBook` has `isInvalid == true`.

**Interfaces produced:**
```dart
// In lib/domain/local_library.dart
class LocalLibraryValidator {
  /// Returns a new tree with isInvalid / hasWarning flags set.
  /// Pure function — no I/O.
  LibraryFolder validate(LibraryFolder root);
}
```

- [ ] **Step 1: Create failing test file `test/domain/local_library_validator_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/local_library.dart';

LibraryBook _book(String relativePath, LocalBookMetadata meta) => LibraryBook(
      relativePath: relativePath,
      documentUri: 'content://fake/$relativePath',
      parentUri: 'content://fake/parent',
      meta: meta,
      isInvalid: false,
    );

LibraryFolder _folder(String name, List<LibraryNode> children) => LibraryFolder(
      name: name,
      children: children,
      hasWarning: false,
    );

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

      test('invalid when author name mismatches (case-sensitive char difference)', () {
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
      });

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

      test('folder hasWarning is false when all descendant books are valid', () {
        const valid = LocalBookMetadata(title: 'T', author: 'Jane Doe');
        final root = _folder('root', [
          _folder('Jane Doe', [
            _book('Jane Doe/book1.fb2', valid),
            _book('Jane Doe/book2.fb2', valid),
          ]),
        ]);
        final result = _validator.validate(root);
        expect(result.hasWarning, isFalse);
      });
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (class not found)**

```powershell
flutter test test/domain/local_library_validator_test.dart
```

- [ ] **Step 3: Add `LocalLibraryValidator` to `lib/domain/local_library.dart`**

Add this class at the bottom of the file:

```dart
class LocalLibraryValidator {
  const LocalLibraryValidator();

  /// Returns a new annotated tree. Pure function — no I/O.
  LibraryFolder validate(LibraryFolder root) {
    final annotated = _annotateFolder(root);
    return annotated;
  }

  LibraryFolder _annotateFolder(LibraryFolder folder) {
    final annotatedChildren = folder.children.map(_annotateNode).toList();
    final hasWarning = annotatedChildren.any((node) => switch (node) {
          LibraryBook b => b.isInvalid,
          LibraryFolder f => f.hasWarning,
        });
    return folder.copyWith(children: annotatedChildren, hasWarning: hasWarning);
  }

  LibraryNode _annotateNode(LibraryNode node) => switch (node) {
        LibraryBook b => b.copyWith(isInvalid: !_isValid(b)),
        LibraryFolder f => _annotateFolder(f),
      };

  bool _isValid(LibraryBook book) {
    final parts = book.relativePath.split('/');
    // Last part is the filename; preceding parts are folder segments
    final segments = parts.sublist(0, parts.length - 1);
    final depth = segments.length;
    final author = book.meta.author.toLowerCase().trim();
    final series = book.meta.series?.toLowerCase().trim();

    return switch (depth) {
      0 => false,
      1 => series == null &&
          segments[0].toLowerCase().trim() == author,
      2 => series != null &&
          segments[0].toLowerCase().trim() == author &&
          segments[1].toLowerCase().trim() == series,
      _ => false,
    };
  }
}
```

- [ ] **Step 4: Run test — expect PASS**

```powershell
flutter test test/domain/local_library_validator_test.dart
```

- [ ] **Step 5: Run quality gate**

```powershell
dart run tool/check.dart
```

- [ ] **Step 6: Commit**

```powershell
git add lib/domain/local_library.dart test/domain/local_library_validator_test.dart
git commit -m "feat: add LocalLibraryValidator pure domain function"
```

---

### Task 2: `LocalLibraryFixer` — domain orchestrator

**Files:**
- Modify: `lib/domain/local_library.dart`
- Create: `test/domain/local_library_fixer_test.dart`

**Fix rule per book** (depth derived from `relativePath`):

```
depth 0  → skip
depth 1  → author = segments[0], clear series + seriesIndex
depth 2  → author = segments[0], series = segments[1], keep existing seriesIndex
depth >2 → skip
```

For each non-skipped book: read bytes, patch via `Fb2MetadataWriter`, write back via `LocalBookReadWriter`, update cache via `SqfliteLocalLibraryCache`.

**Interfaces produced:**
```dart
// In lib/domain/local_library.dart
class FixResult {
  final int fixed;
  final int skipped;
}

class LocalLibraryFixer {
  final LocalBookReadWriter readWriter;
  final Fb2MetadataWriter writer;
  final SqfliteLocalLibraryCache cache;
  const LocalLibraryFixer({required this.readWriter, required this.writer, required this.cache});

  Future<(FixResult, LibraryFolder)> fix(LibraryFolder root);
}
```

Note: `fix` returns both the `FixResult` summary AND the updated `LibraryFolder` tree with new metadata applied in-memory.

- [ ] **Step 1: Create failing test file `test/domain/local_library_fixer_test.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/fb2_metadata_parser.dart';
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

LibraryFolder _folder(String name, List<LibraryNode> children) => LibraryFolder(
      name: name,
      children: children,
      hasWarning: true,
    );

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
            _folder('A/B/C', [
              _invalidBook('A/B/C/book.fb2', meta),
            ]),
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
```

- [ ] **Step 2: Run test — expect FAIL (class not found)**

```powershell
flutter test test/domain/local_library_fixer_test.dart
```

- [ ] **Step 3: Add `FixResult` and `LocalLibraryFixer` to `lib/domain/local_library.dart`**

Add imports at the top of the file:
```dart
import 'dart:typed_data';
import 'package:opds_browser/data/fb2_metadata_writer.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
```

Add these classes at the bottom of the file:

```dart
class FixResult {
  final int fixed;
  final int skipped;
  const FixResult({required this.fixed, required this.skipped});
}

class LocalLibraryFixer {
  final LocalBookReadWriter readWriter;
  final Fb2MetadataWriter writer;
  final SqfliteLocalLibraryCache cache;

  const LocalLibraryFixer({
    required this.readWriter,
    required this.writer,
    required this.cache,
  });

  Future<(FixResult, LibraryFolder)> fix(LibraryFolder root) async {
    var fixed = 0;
    var skipped = 0;

    Future<LibraryFolder> processFolder(LibraryFolder folder) async {
      final newChildren = <LibraryNode>[];
      for (final node in folder.children) {
        switch (node) {
          case LibraryBook b when b.isInvalid:
            final result = await _fixBook(b);
            if (result != null) {
              newChildren.add(b.copyWith(meta: result));
              fixed++;
            } else {
              newChildren.add(b);
              skipped++;
            }
          case LibraryFolder f:
            newChildren.add(await processFolder(f));
          default:
            newChildren.add(node);
        }
      }
      return folder.copyWith(children: newChildren);
    }

    final newRoot = await processFolder(root);
    return (FixResult(fixed: fixed, skipped: skipped), newRoot);
  }

  Future<LocalBookMetadata?> _fixBook(LibraryBook book) async {
    final parts = book.relativePath.split('/');
    final segments = parts.sublist(0, parts.length - 1);
    final depth = segments.length;

    final LocalBookMetadata newMeta;
    switch (depth) {
      case 0:
        return null;
      case 1:
        newMeta = book.meta.copyWith(
          author: segments[0],
          clearSeries: true,
          clearSeriesIndex: true,
        );
      case 2:
        newMeta = book.meta.copyWith(
          author: segments[0],
          series: segments[1],
        );
      default:
        return null;
    }

    final isZip = book.relativePath.toLowerCase().endsWith('.fb2.zip');
    final fileName = parts.last;
    final mimeType = isZip ? 'application/zip' : 'application/x-fictionbook+xml';

    final bytes = await readWriter.readBytes(book.documentUri);
    final patched = writer.patchBytes(bytes, newMeta, isZip: isZip);
    await readWriter.writeBytes(
      book.documentUri,
      book.parentUri,
      fileName,
      mimeType,
      patched,
    );
    await cache.put(book.relativePath, newMeta);
    return newMeta;
  }
}
```

- [ ] **Step 4: Run test — expect PASS**

```powershell
flutter test test/domain/local_library_fixer_test.dart
```

- [ ] **Step 5: Run quality gate**

```powershell
dart run tool/check.dart
```

- [ ] **Step 6: Commit**

```powershell
git add lib/domain/local_library.dart test/domain/local_library_fixer_test.dart
git commit -m "feat: add LocalLibraryFixer domain orchestrator"
```

---

### Task 3: Wire `validate()` and `fix()` into `LocalLibraryNotifier`

**Files:**
- Modify: `lib/ui/local_library_screen.dart`
- Modify: `test/ui/local_library_notifier_test.dart`

**Interfaces produced:**
```dart
// In LocalLibraryNotifier:
void validate();                    // synchronous — pure in-memory
Future<void> fix(BuildContext context);  // async — I/O per invalid book
```

- [ ] **Step 1: Write failing tests — add to `test/ui/local_library_notifier_test.dart`**

Add this group at the bottom of `main()`:

```dart
group('validate', () {
  test('sets validationRun and annotates invalid books', () async {
    // depth-1 book with wrong author
    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file]);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();

    // Inject a book with wrong author into cache
    final cache = c.read(localLibraryCacheProvider);
    await cache.put(
      'Jane Doe/book.fb2',
      const LocalBookMetadata(title: 'T', author: 'Wrong Name'),
    );

    // Re-scan to pick up the cache
    await c.read(localLibraryNotifierProvider.notifier).refresh();

    c.read(localLibraryNotifierProvider.notifier).validate();

    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    expect(state.validationRun, isTrue);

    final book = state.root.children
        .whereType<LibraryFolder>()
        .first
        .children
        .whereType<LibraryBook>()
        .first;
    expect(book.isInvalid, isTrue);
  });

  test('marks valid book as not invalid', () async {
    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file]);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();

    // Inject matching metadata into cache
    final cache = c.read(localLibraryCacheProvider);
    await cache.put(
      'Jane Doe/book.fb2',
      const LocalBookMetadata(title: 'T', author: 'Jane Doe'),
    );

    await c.read(localLibraryNotifierProvider.notifier).refresh();
    c.read(localLibraryNotifierProvider.notifier).validate();

    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    final book = state.root.children
        .whereType<LibraryFolder>()
        .first
        .children
        .whereType<LibraryBook>()
        .first;
    expect(book.isInvalid, isFalse);
  });
});

group('fix', () {
  test('calls writer for invalid books and re-validates', () async {
    final rw = FakeReadWriter();
    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file], readWriter: rw);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();

    // Inject wrong author so book is invalid after validate
    final cache = c.read(localLibraryCacheProvider);
    await cache.put(
      'Jane Doe/book.fb2',
      const LocalBookMetadata(title: 'T', author: 'Wrong'),
    );
    await c.read(localLibraryNotifierProvider.notifier).refresh();
    c.read(localLibraryNotifierProvider.notifier).validate();

    await c.read(localLibraryNotifierProvider.notifier).fix();

    // Writer was called
    expect(rw.writtenPaths, isNotEmpty);

    // After fix, re-validation runs and book should now be valid
    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    expect(state.validationRun, isTrue);
    final book = state.root.children
        .whereType<LibraryFolder>()
        .first
        .children
        .whereType<LibraryBook>()
        .first;
    expect(book.isInvalid, isFalse);
  });
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```powershell
flutter test test/ui/local_library_notifier_test.dart
```

- [ ] **Step 3: Add `validate()` and `fix()` methods to `LocalLibraryNotifier` in `lib/ui/local_library_screen.dart`**

Add imports to the file:
```dart
import 'package:opds_browser/domain/local_library.dart'; // already present
```

Add these methods inside `LocalLibraryNotifier`:

```dart
void validate() {
  final current = state;
  if (current is! LibraryReady) return;
  const validator = LocalLibraryValidator();
  final annotated = validator.validate(current.root);
  state = current.copyWith(root: annotated, validationRun: true);
}

Future<(int fixed, int skipped)> fix() async {
  final current = state;
  if (current is! LibraryReady) return (0, 0);

  final rw = ref.read(localBookReadWriterProvider);
  final writer = ref.read(fb2MetadataWriterProvider);
  final cache = ref.read(localLibraryCacheProvider);

  final fixer = LocalLibraryFixer(readWriter: rw, writer: writer, cache: cache);
  final (result, newRoot) = await fixer.fix(current.root);

  // Re-validate after fix to refresh isInvalid and hasWarning flags
  const validator = LocalLibraryValidator();
  final revalidated = validator.validate(newRoot);
  state = current.copyWith(root: revalidated, validationRun: true);

  return (result.fixed, result.skipped);
}
```

- [ ] **Step 4: Run tests — expect PASS**

```powershell
flutter test test/ui/local_library_notifier_test.dart
```

- [ ] **Step 5: Run quality gate**

```powershell
dart run tool/check.dart
```

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/local_library_screen.dart test/ui/local_library_notifier_test.dart
git commit -m "feat: wire validate() and fix() into LocalLibraryNotifier"
```

---

### Task 4: Add Validate and Fix AppBar buttons to `LocalLibraryScreen`

**Files:**
- Modify: `lib/ui/local_library_screen.dart`

The AppBar already has a Refresh button from Plan 03. Add Validate and Fix as additional actions.

Rules:
- Refresh, Validate, Fix all disabled during `LibraryScanning`
- Fix also disabled when `validationRun == false`
- After Fix completes, show a `SnackBar`: `"Fixed N book(s), skipped M"`

- [ ] **Step 1: Update `LocalLibraryScreen.build()` AppBar in `lib/ui/local_library_screen.dart`**

Replace the AppBar actions list. The full AppBar block should look like:

```dart
AppBar(
  title: const Text('Local Library'),
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Refresh',
      onPressed: isScanning
          ? null
          : () => ref.read(localLibraryNotifierProvider.notifier).refresh(),
    ),
    IconButton(
      icon: const Icon(Icons.check_circle_outline),
      tooltip: 'Validate',
      onPressed: isScanning
          ? null
          : () => ref.read(localLibraryNotifierProvider.notifier).validate(),
    ),
    IconButton(
      icon: const Icon(Icons.auto_fix_high),
      tooltip: 'Fix',
      onPressed: (isScanning || !validationRun)
          ? null
          : () => _runFix(context, ref),
    ),
  ],
),
```

Add a helper method to the screen widget (not the notifier):

```dart
Future<void> _runFix(BuildContext context, WidgetRef ref) async {
  final (fixed, skipped) = await ref.read(localLibraryNotifierProvider.notifier).fix();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Fixed $fixed book(s), skipped $skipped')),
  );
}
```

Update the local `isScanning` and `validationRun` variables at the top of `build()`:

```dart
final libraryState = ref.watch(localLibraryNotifierProvider);
final isScanning = libraryState is LibraryScanning;
final validationRun = libraryState is LibraryReady && libraryState.validationRun;
```

- [ ] **Step 2: Run quality gate**

```powershell
dart run tool/check.dart
```

- [ ] **Step 3: Commit**

```powershell
git add lib/ui/local_library_screen.dart
git commit -m "feat: add Validate and Fix AppBar buttons to LocalLibraryScreen"
```

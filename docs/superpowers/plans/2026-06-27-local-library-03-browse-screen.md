# Local Library — Plan 03: Library Browse Screen (Step 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the SAF library scanner, the `LocalLibraryNotifier` state machine, and the collapsible tree view screen that shows cached FB2 metadata for all books in the library folder.

**Architecture:** `SafLocalLibraryScanner` is the real SAF implementation of `LocalLibraryScanner` — it cannot be tested on host. All notifier tests use a fake scanner. The notifier is a `Notifier<LocalLibraryState>` that starts scanning on `build()` and exposes `refresh()`.

**Tech Stack:** `saf_util`, `saf_stream`, `flutter_riverpod`, `go_router`, existing `SqfliteLocalLibraryCache`, `Fb2MetadataParser`.

## Global Constraints

- Android only — no iOS-specific code.
- `dart run tool/check.dart` must be clean after every task.
- Commit after every task.

## Prerequisites

- Plan 01 complete (setup screen, `/library` route stub)
- Plan 02 complete (`LocalBookMetadata`, `LibraryNode`, `LocalLibraryScanner`, `Fb2MetadataParser`, `SqfliteLocalLibraryCache`)

---

## File Map

| File | Action |
|------|--------|
| `lib/data/saf_local_library_scanner.dart` | new — real SAF scanner |
| `lib/data/saf_book_read_writer.dart` | new — SAF read/write stub (used in plan 04) |
| `lib/ui/providers.dart` | modify — add library providers |
| `lib/ui/local_library_screen.dart` | new — screen + notifier |
| `test/ui/local_library_notifier_test.dart` | new |

---

### Task 1: `SafLocalLibraryScanner` (real SAF implementation — no host tests)

**Files:**
- Create: `lib/data/saf_local_library_scanner.dart`
- Create: `lib/data/saf_book_read_writer.dart`

These classes use platform channels (`saf_util`, `saf_stream`) and cannot be unit tested on the host. They are tested indirectly through the notifier tests with fakes.

- [ ] **Step 1: Create `lib/data/saf_local_library_scanner.dart`**

```dart
import 'package:opds_browser/domain/local_library.dart';
import 'package:saf_util/saf_util.dart';

class SafLocalLibraryScanner implements LocalLibraryScanner {
  @override
  Stream<LibraryFile> scan(String treeUri) => _scanDirectory(treeUri, treeUri, '');

  Stream<LibraryFile> _scanDirectory(
    String treeUri,
    String dirUri,
    String prefix,
  ) async* {
    // SafUtil().list returns children of a SAF directory.
    // Check saf_util docs / source for exact method name and SafDocumentFile fields.
    final children = await SafUtil().list(dirUri);
    for (final child in children) {
      if (child.isDirectory == true) {
        final childPrefix = prefix.isEmpty ? child.name : '$prefix/${child.name}';
        yield* _scanDirectory(treeUri, child.uri, childPrefix);
      } else {
        final name = (child.name).toLowerCase();
        if (name.endsWith('.fb2') || name.endsWith('.fb2.zip')) {
          final relPath = prefix.isEmpty ? child.name : '$prefix/${child.name}';
          yield LibraryFile(
            relativePath: relPath,
            documentUri: child.uri,
            parentUri: dirUri,
          );
        }
      }
    }
  }
}
```

> **Note:** `SafUtil().list(dirUri)` — verify exact method name in saf_util 3.x source.
> `SafDocumentFile` fields used: `.name` (String), `.uri` (String), `.isDirectory` (bool?).
> If the method is named differently (e.g. `listFiles`, `getChildren`), update accordingly.

- [ ] **Step 2: Create `lib/data/saf_book_read_writer.dart`**

```dart
import 'dart:typed_data';
import 'package:opds_browser/domain/local_library.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

class SafBookReadWriter implements LocalBookReadWriter {
  final _safStream = SafStream();
  final _safUtil = SafUtil();

  @override
  Future<Uint8List> readBytes(String documentUri) async {
    // SafStream().readFile returns a Stream<List<int>>.
    // Verify exact method name in saf_stream 3.x docs.
    final stream = _safStream.readFile(documentUri);
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
    }
    return Uint8List.fromList(buffer);
  }

  @override
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    // Strategy: delete existing SAF document, then write new file to parent.
    // If saf_util provides a delete method, use it. Otherwise check saf_stream
    // for a direct-to-URI write (truncate) mode.
    //
    // Option A (if saf_util has delete):
    //   await _safUtil.delete(documentUri);
    //   await _safStream.writeFileBytes(parentUri, fileName, mimeType, bytes);
    //
    // Option B (if saf_stream has direct-URI write):
    //   await _safStream.writeExistingFileBytes(documentUri, mimeType, bytes);
    //
    // Verify the correct approach in the package source before implementing.
    throw UnimplementedError('Implement after verifying saf_util/saf_stream API');
  }
}
```

> **Note for implementer:** Check the `saf_util` and `saf_stream` source for:
> - `SafUtil().delete(String documentUri)` or similar for deleting a document
> - `SafStream().writeExistingFileBytes(String docUri, String mimeType, Uint8List bytes)` for overwriting
> Fill in the `writeBytes` body before Plan 04.

- [ ] **Step 3: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 4: Commit**

```powershell
git add lib/data/saf_local_library_scanner.dart lib/data/saf_book_read_writer.dart
git commit -m "feat: add SafLocalLibraryScanner and SafBookReadWriter stubs"
```

---

### Task 2: Add library providers to `providers.dart`

**Files:**
- Modify: `lib/ui/providers.dart`

**Interfaces produced (for later tasks):**
```dart
final localLibraryScannerProvider = Provider<LocalLibraryScanner>(...);
final localLibraryCacheProvider = Provider<SqfliteLocalLibraryCache>(...);
final fb2MetadataParserProvider = Provider<Fb2MetadataParser>(...);
final localBookReadWriterProvider = Provider<LocalBookReadWriter>(...);
final localLibraryNotifierProvider = NotifierProvider<LocalLibraryNotifier, LocalLibraryState>(...);
```

- [ ] **Step 1: Add the following providers to `lib/ui/providers.dart`**

Add these imports at the top:
```dart
import 'package:opds_browser/data/fb2_metadata_parser.dart';
import 'package:opds_browser/data/saf_book_read_writer.dart';
import 'package:opds_browser/data/saf_local_library_scanner.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
import 'package:opds_browser/domain/local_library.dart';
```

Add these providers at the bottom of the file (before the end):
```dart
// ── Local library ─────────────────────────────────────────────────────────────

final localLibraryScannerProvider = Provider<LocalLibraryScanner>(
  (ref) => SafLocalLibraryScanner(),
);

final localLibraryCacheProvider = Provider<SqfliteLocalLibraryCache>(
  (ref) => SqfliteLocalLibraryCache(ref.watch(appDatabaseProvider)),
);

final fb2MetadataParserProvider = Provider<Fb2MetadataParser>(
  (ref) => Fb2MetadataParser(),
);

final localBookReadWriterProvider = Provider<LocalBookReadWriter>(
  (ref) => SafBookReadWriter(),
);

final localLibraryNotifierProvider =
    NotifierProvider<LocalLibraryNotifier, LocalLibraryState>(
      LocalLibraryNotifier.new,
    );
```

- [ ] **Step 2: Run `dart run tool/check.dart`** — will fail until `LocalLibraryNotifier` is defined (next task)

---

### Task 3: `LocalLibraryNotifier` — scan, cache lookup, tree building, refresh

**Files:**
- Create: `lib/ui/local_library_screen.dart` (notifier + UI in same file)
- Create: `test/ui/local_library_notifier_test.dart`

**Interfaces consumed:**
```dart
// From Plan 02:
LocalBookMetadata, LibraryFile, LibraryNode, LibraryFolder, LibraryBook, LocalLibraryScanner
SqfliteLocalLibraryCache.get(), .put(), .deleteAll()
Fb2MetadataParser.parseBytes()

// From providers.dart:
localLibraryScannerProvider, localLibraryCacheProvider, fb2MetadataParserProvider
settingsProvider  (to get treeUri)
```

- [ ] **Step 1: Write the failing notifier tests**

Create `test/ui/local_library_notifier_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/fb2_metadata_parser.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/local_library_screen.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opds_browser/data/app_database.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeScanner implements LocalLibraryScanner {
  final List<LibraryFile> files;
  FakeScanner(this.files);

  @override
  Stream<LibraryFile> scan(String treeUri) => Stream.fromIterable(files);
}

class FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> load() async =>
      const AppSettings(target: CustomSafFolder('content://tree/root', 'Lib'));
  @override
  Future<void> save(AppSettings settings) async {}
}

// Minimal FB2 XML bytes (bypasses real SAF — parser is called only on cache miss)
Uint8List _fb2Bytes(String title, String author, {String? series, int? seriesNum}) {
  final seriesEl = series != null
      ? '<sequence name="$series" number="${seriesNum ?? 1}"/>'
      : '';
  final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info>
<author><last-name>$author</last-name></author>
<book-title>$title</book-title>
$seriesEl
</title-info></description>
<body><section><p>.</p></section></body>
</FictionBook>''';
  return Uint8List.fromList(xml.codeUnits);
}

// ── Test helper ───────────────────────────────────────────────────────────────

ProviderContainer _makeContainer({
  required List<LibraryFile> files,
  SqfliteLocalLibraryCache? cache,
}) {
  final db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  final realCache = cache ?? SqfliteLocalLibraryCache(db);
  return ProviderContainer(
    overrides: [
      localLibraryScannerProvider.overrideWithValue(FakeScanner(files)),
      localLibraryCacheProvider.overrideWithValue(realCache),
      fb2MetadataParserProvider.overrideWithValue(Fb2MetadataParser()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      safPermissionCheckerProvider.overrideWithValue((_) async => true),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('initial state is LibraryScanning', () {
    final c = _makeContainer(files: []);
    addTearDown(c.dispose);
    expect(c.read(localLibraryNotifierProvider), isA<LibraryScanning>());
  });

  test('transitions to LibraryReady after scan of empty library', () async {
    final c = _makeContainer(files: []);
    addTearDown(c.dispose);
    // Wait for scan to complete
    await Future<void>.delayed(Duration.zero);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();
    expect(c.read(localLibraryNotifierProvider), isA<LibraryReady>());
  });

  test('LibraryReady contains books from scanned files', () async {
    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file]);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();
    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    final folder = state.root.children.whereType<LibraryFolder>().first;
    expect(folder.name, 'Jane Doe');
    final book = folder.children.whereType<LibraryBook>().first;
    expect(book.relativePath, 'Jane Doe/book.fb2');
  });

  test('cache hit avoids re-parsing — parser not called for cached file', () async {
    final db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final cache = SqfliteLocalLibraryCache(db);
    await cache.put('Jane Doe/book.fb2', const LocalBookMetadata(title: 'Cached Title', author: 'Cached Author'));

    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file], cache: cache);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();

    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    final book = state.root.children
        .whereType<LibraryFolder>()
        .first
        .children
        .whereType<LibraryBook>()
        .first;
    expect(book.meta.title, 'Cached Title');
  });

  test('refresh clears cache and rescans', () async {
    final db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final cache = SqfliteLocalLibraryCache(db);
    await cache.put('Jane Doe/book.fb2', const LocalBookMetadata(title: 'Old Cache', author: 'X'));

    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file], cache: cache);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();

    await c.read(localLibraryNotifierProvider.notifier).refresh();

    // After refresh, cache was cleared; since FakeScanner provides no bytes,
    // book gets placeholder metadata
    expect(await cache.get('Jane Doe/book.fb2'), isNull);
  });

  test('validationRun starts as false', () async {
    final c = _makeContainer(files: []);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();
    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    expect(state.validationRun, isFalse);
  });
}
```

> **Note on `waitForReady()`:** The notifier must expose a helper that completes once the state is `LibraryReady` — see implementation below.

- [ ] **Step 2: Run test — expect FAIL**

```powershell
flutter test test/ui/local_library_notifier_test.dart
```

- [ ] **Step 3: Create `lib/ui/local_library_screen.dart`**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/data/fb2_metadata_parser.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/ui/providers.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class LocalLibraryState {}

class LibraryScanning extends LocalLibraryState {
  LibraryScanning({required this.scanned});
  final int scanned;
}

class LibraryReady extends LocalLibraryState {
  LibraryReady({required this.root, required this.validationRun});
  final LibraryFolder root;
  final bool validationRun;

  LibraryReady copyWith({LibraryFolder? root, bool? validationRun}) =>
      LibraryReady(
        root: root ?? this.root,
        validationRun: validationRun ?? this.validationRun,
      );
}

class LibraryError extends LocalLibraryState {
  LibraryError(this.message);
  final String message;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class LocalLibraryNotifier extends Notifier<LocalLibraryState> {
  Completer<void>? _readyCompleter;

  @override
  LocalLibraryState build() {
    _readyCompleter = Completer<void>();
    unawaited(_scan());
    return LibraryScanning(scanned: 0);
  }

  /// Used in tests to await the first LibraryReady transition.
  Future<void> waitForReady() => _readyCompleter?.future ?? Future.value();

  Future<void> _scan() async {
    try {
      final settings = ref.read(settingsProvider).value;
      final treeUri = settings?.target?.uriString;
      if (treeUri == null) {
        state = LibraryError('No library folder configured.');
        _readyCompleter?.complete();
        return;
      }

      final scanner = ref.read(localLibraryScannerProvider);
      final cache = ref.read(localLibraryCacheProvider);
      final parser = ref.read(fb2MetadataParserProvider);

      final files = <LibraryFile>[];
      await for (final file in scanner.scan(treeUri)) {
        files.add(file);
        state = LibraryScanning(scanned: files.length);
      }

      final metaMap = <String, LocalBookMetadata>{};
      for (final file in files) {
        final cached = await cache.get(file.relativePath);
        if (cached != null) {
          metaMap[file.relativePath] = cached;
        } else {
          try {
            final rw = ref.read(localBookReadWriterProvider);
            final bytes = await rw.readBytes(file.documentUri);
            final isZip = file.relativePath.toLowerCase().endsWith('.fb2.zip');
            final meta = parser.parseBytes(bytes, isZip: isZip);
            metaMap[file.relativePath] = meta;
            await cache.put(file.relativePath, meta);
          } catch (_) {
            final fallback = LocalBookMetadata(
              title: file.relativePath.split('/').last,
              author: '',
            );
            metaMap[file.relativePath] = fallback;
            await cache.put(file.relativePath, fallback);
          }
        }
      }

      final root = _buildTree(files, metaMap);
      state = LibraryReady(root: root, validationRun: false);
    } catch (e) {
      state = LibraryError(e.toString());
    } finally {
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.complete();
      }
    }
  }

  Future<void> refresh() async {
    final cache = ref.read(localLibraryCacheProvider);
    await cache.deleteAll();
    _readyCompleter = Completer<void>();
    state = LibraryScanning(scanned: 0);
    await _scan();
  }

  LibraryFolder _buildTree(
    List<LibraryFile> files,
    Map<String, LocalBookMetadata> metaMap,
  ) {
    final root = _FolderBuilder('');
    for (final file in files) {
      final segments = file.relativePath.split('/');
      final meta = metaMap[file.relativePath] ??
          LocalBookMetadata(title: segments.last, author: '');
      final book = LibraryBook(
        relativePath: file.relativePath,
        documentUri: file.documentUri,
        parentUri: file.parentUri,
        meta: meta,
      );
      root.addBook(segments.sublist(0, segments.length - 1), book);
    }
    return root.build();
  }
}

class _FolderBuilder {
  _FolderBuilder(this.name);
  final String name;
  final Map<String, _FolderBuilder> _subFolders = {};
  final List<LibraryBook> _books = [];

  void addBook(List<String> folderSegments, LibraryBook book) {
    if (folderSegments.isEmpty) {
      _books.add(book);
    } else {
      _subFolders
          .putIfAbsent(folderSegments.first, () => _FolderBuilder(folderSegments.first))
          .addBook(folderSegments.sublist(1), book);
    }
  }

  LibraryFolder build() => LibraryFolder(
    name: name,
    children: [
      ..._subFolders.values.map((f) => f.build()),
      ..._books,
    ],
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});

  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  final Set<LibraryFolder> _collapsed = {};

  void _toggleFolder(LibraryFolder folder) {
    setState(() {
      if (_collapsed.contains(folder)) {
        _collapsed.remove(folder);
      } else {
        _collapsed.add(folder);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final libState = ref.watch(localLibraryNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: libState is LibraryScanning
                ? null
                : () => ref.read(localLibraryNotifierProvider.notifier).refresh(),
          ),
        ],
      ),
      body: switch (libState) {
        LibraryScanning(:final scanned) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Scanning… $scanned files found'),
            ],
          ),
        ),
        LibraryError(:final message) => Center(child: Text('Error: $message')),
        LibraryReady(:final root, :final validationRun) => _buildTree(root, validationRun),
      },
    );
  }

  Widget _buildTree(LibraryFolder root, bool validationRun) {
    final rows = _flattenTree(root, -1, _collapsed); // depth -1 so root children start at 0
    if (rows.isEmpty) {
      return const Center(child: Text('No books found in library.'));
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final (node, depth) = rows[i];
        return switch (node) {
          LibraryFolder() => _FolderTile(
            folder: node,
            depth: depth,
            validationRun: validationRun,
            isCollapsed: _collapsed.contains(node),
            onToggle: () => _toggleFolder(node),
          ),
          LibraryBook() => _BookTile(
            book: node,
            depth: depth,
            validationRun: validationRun,
          ),
        };
      },
    );
  }
}

List<(LibraryNode, int)> _flattenTree(
  LibraryNode node,
  int depth,
  Set<LibraryFolder> collapsed,
) {
  return switch (node) {
    LibraryBook() => [(node, depth)],
    LibraryFolder() => [
      if (depth >= 0) (node, depth),
      if (depth < 0 || !collapsed.contains(node))
        ...node.children.expand((c) => _flattenTree(c, depth + 1, collapsed)),
    ],
  };
}

// ── Folder tile ───────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.depth,
    required this.validationRun,
    required this.isCollapsed,
    required this.onToggle,
  });

  final LibraryFolder folder;
  final int depth;
  final bool validationRun;
  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bookCount = _countBooks(folder);
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        leading: Icon(isCollapsed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down),
        title: Text(folder.name),
        subtitle: Text('$bookCount book${bookCount == 1 ? '' : 's'}'),
        trailing: (validationRun && folder.hasWarning)
            ? const Icon(Icons.warning_amber_rounded, color: Colors.amber)
            : null,
        onTap: onToggle,
      ),
    );
  }
}

// ── Book tile ─────────────────────────────────────────────────────────────────

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.depth,
    required this.validationRun,
  });

  final LibraryBook book;
  final int depth;
  final bool validationRun;

  @override
  Widget build(BuildContext context) {
    final meta = book.meta;
    final seriesText = meta.series != null
        ? (meta.seriesIndex != null ? '${meta.series} #${meta.seriesIndex}' : meta.series!)
        : null;
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        leading: const Icon(Icons.book),
        title: Text(meta.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (meta.author.isNotEmpty) Text(meta.author),
            if (seriesText != null) Text(seriesText),
          ],
        ),
        isThreeLine: meta.author.isNotEmpty && seriesText != null,
        trailing: (validationRun && book.isInvalid)
            ? const Icon(Icons.warning_amber_rounded, color: Colors.amber)
            : null,
      ),
    );
  }
}

int _countBooks(LibraryNode node) => switch (node) {
  LibraryBook() => 1,
  LibraryFolder() => node.children.fold(0, (sum, c) => sum + _countBooks(c)),
};
```

- [ ] **Step 4: Wire `LocalLibraryScreen` into the `/library` route in `lib/app.dart`**

Replace the stub route:
```dart
GoRoute(
  path: '/library',
  builder: (_, __) => const LocalLibraryScreen(),
),
```

Also add import:
```dart
import 'package:opds_browser/ui/local_library_screen.dart';
```

- [ ] **Step 5: Run notifier tests — expect PASS**

```powershell
flutter test test/ui/local_library_notifier_test.dart
```

- [ ] **Step 6: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 7: Commit**

```powershell
git add lib/ui/local_library_screen.dart lib/ui/providers.dart lib/app.dart test/ui/local_library_notifier_test.dart
git commit -m "feat: add library browse screen with scan, cache, and collapsible tree view"
```

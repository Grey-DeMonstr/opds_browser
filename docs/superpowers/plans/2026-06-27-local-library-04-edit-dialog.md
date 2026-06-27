# Local Library — Plan 04: Edit Metadata Dialog (Step 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an edit-metadata bottom sheet that lets the user update title, author, series, and series # for any FB2/fb2.zip book, writes changes back to the file via SAF, updates the SQLite cache, and refreshes the in-memory tree state.

**Architecture:** The sheet is stateful (local form state), calls a method on `LocalLibraryNotifier` to persist, which in turn calls `Fb2MetadataWriter` and `LocalBookReadWriter`. If `validationRun` is true the notifier re-evaluates the book's validity after saving.

**Tech Stack:** `Fb2MetadataWriter` (Plan 02), `LocalBookReadWriter` / `SafBookReadWriter` (Plan 03), `SqfliteLocalLibraryCache` (Plan 02), Riverpod, Flutter form widgets.

## Global Constraints

- Android only.
- `dart run tool/check.dart` must be clean after every task.
- Commit after every task.

## Prerequisites

- Plan 02 complete (`Fb2MetadataWriter`, `SqfliteLocalLibraryCache`)
- Plan 03 complete (`LocalLibraryScreen`, `LocalLibraryNotifier`, `SafBookReadWriter` stub)
- **Before this plan:** complete the `SafBookReadWriter.writeBytes()` body (see Plan 03 Task 1 notes).

---

## File Map

| File | Action |
|------|--------|
| `lib/data/saf_book_read_writer.dart` | modify — implement `writeBytes` |
| `lib/ui/widgets/edit_book_metadata_sheet.dart` | new |
| `lib/ui/local_library_screen.dart` | modify — wire tap → sheet, add `updateBook()` to notifier |
| `test/ui/local_library_notifier_test.dart` | modify — add edit tests |

---

### Task 1: Implement `SafBookReadWriter.writeBytes`

**Files:**
- Modify: `lib/data/saf_book_read_writer.dart`

Before implementing, verify the saf_util/saf_stream API:

```powershell
# Check available methods on SafUtil and SafStream:
Get-ChildItem "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev" -Filter "saf_util*" -Recurse -Directory | Select-Object -First 1 | Get-ChildItem -Recurse -Filter "*.dart" | Select-String "void\|Future" | Select-String -NotMatch "test"
```

- [ ] **Step 1: Implement `writeBytes` in `lib/data/saf_book_read_writer.dart`**

Replace the `writeBytes` method body. Use whichever approach the package API supports:

**Option A — if saf_util has `delete(uri)` and saf_stream creates file in parent:**
```dart
@override
Future<void> writeBytes(
  String documentUri,
  String parentUri,
  String fileName,
  String mimeType,
  Uint8List bytes,
) async {
  // Delete the existing document first, then write to parent.
  await _safUtil.delete(documentUri);
  await _safStream.writeFileBytes(parentUri, fileName, mimeType, bytes);
}
```

**Option B — if saf_stream supports direct URI write (truncate mode):**
```dart
@override
Future<void> writeBytes(
  String documentUri,
  String parentUri,
  String fileName,
  String mimeType,
  Uint8List bytes,
) async {
  // Write directly to the existing document URI (truncates content).
  await _safStream.writeExistingFileBytes(documentUri, mimeType, bytes);
}
```

Pick the correct option after checking the package source.

- [ ] **Step 2: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 3: Commit**

```powershell
git add lib/data/saf_book_read_writer.dart
git commit -m "feat: implement SafBookReadWriter.writeBytes"
```

---

### Task 2: Add `updateBook` to `LocalLibraryNotifier` + tests

**Files:**
- Modify: `lib/ui/local_library_screen.dart` (add `updateBook` method to `LocalLibraryNotifier`)
- Modify: `test/ui/local_library_notifier_test.dart`

**Interfaces produced:**
```dart
// In LocalLibraryNotifier:
Future<void> updateBook(LibraryBook book, LocalBookMetadata newMeta);
```

- [ ] **Step 1: Write failing tests — add to `test/ui/local_library_notifier_test.dart`**

Add a fake `LocalBookReadWriter` at the top:
```dart
class FakeReadWriter implements LocalBookReadWriter {
  final _callLog = <String>[];
  List<String> get writtenPaths => _callLog;

  @override
  Future<Uint8List> readBytes(String documentUri) async => Uint8List(0);

  @override
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    _callLog.add(documentUri);
  }
}
```

Update `_makeContainer` to accept an optional read/writer:
```dart
ProviderContainer _makeContainer({
  required List<LibraryFile> files,
  SqfliteLocalLibraryCache? cache,
  LocalBookReadWriter? readWriter,
}) {
  final db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  final realCache = cache ?? SqfliteLocalLibraryCache(db);
  final rw = readWriter ?? FakeReadWriter();
  return ProviderContainer(
    overrides: [
      localLibraryScannerProvider.overrideWithValue(FakeScanner(files)),
      localLibraryCacheProvider.overrideWithValue(realCache),
      fb2MetadataParserProvider.overrideWithValue(Fb2MetadataParser()),
      localBookReadWriterProvider.overrideWithValue(rw),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      safPermissionCheckerProvider.overrideWithValue((_) async => true),
    ],
  );
}
```

Add these tests at the bottom of `main()`:

```dart
group('updateBook', () {
  test('updates in-memory book meta and cache', () async {
    final db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final cache = SqfliteLocalLibraryCache(db);
    final rw = FakeReadWriter();

    final file = LibraryFile(
      relativePath: 'Jane Doe/book.fb2',
      documentUri: 'content://doc/1',
      parentUri: 'content://dir/1',
    );
    final c = _makeContainer(files: [file], cache: cache, readWriter: rw);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();

    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    final book = state.root.children
        .whereType<LibraryFolder>()
        .first
        .children
        .whereType<LibraryBook>()
        .first;

    const newMeta = LocalBookMetadata(title: 'New Title', author: 'New Author');
    await c.read(localLibraryNotifierProvider.notifier).updateBook(book, newMeta);

    // In-memory tree updated
    final newState = c.read(localLibraryNotifierProvider) as LibraryReady;
    final updatedBook = newState.root.children
        .whereType<LibraryFolder>()
        .first
        .children
        .whereType<LibraryBook>()
        .first;
    expect(updatedBook.meta.title, 'New Title');
    expect(updatedBook.meta.author, 'New Author');

    // Cache updated
    final cached = await cache.get('Jane Doe/book.fb2');
    expect(cached?.title, 'New Title');

    // Writer was called
    expect(rw.writtenPaths, contains('content://doc/1'));
  });
});
```

- [ ] **Step 2: Run test — expect FAIL**

```powershell
flutter test test/ui/local_library_notifier_test.dart
```

- [ ] **Step 3: Add `updateBook` to `LocalLibraryNotifier` in `lib/ui/local_library_screen.dart`**

Add this method inside `LocalLibraryNotifier`:

```dart
Future<void> updateBook(LibraryBook book, LocalBookMetadata newMeta) async {
  final rw = ref.read(localBookReadWriterProvider);
  final writer = ref.read(fb2MetadataWriterProvider);
  final cache = ref.read(localLibraryCacheProvider);

  final isZip = book.relativePath.toLowerCase().endsWith('.fb2.zip');
  final fileName = book.relativePath.split('/').last;
  final mimeType = isZip ? 'application/zip' : 'application/x-fictionbook+xml';

  try {
    final bytes = await rw.readBytes(book.documentUri);
    final patched = writer.patchBytes(bytes, newMeta, isZip: isZip);
    await rw.writeBytes(book.documentUri, book.parentUri, fileName, mimeType, patched);
    await cache.put(book.relativePath, newMeta);

    final currentReady = state;
    if (currentReady is LibraryReady) {
      final newRoot = _replaceBook(currentReady.root, book.relativePath, (b) => b.copyWith(meta: newMeta));
      state = currentReady.copyWith(root: newRoot);
    }
  } catch (e) {
    // Rethrow so the UI can show a snackbar
    rethrow;
  }
}

LibraryFolder _replaceBook(
  LibraryFolder folder,
  String relativePath,
  LibraryBook Function(LibraryBook) update,
) {
  final newChildren = folder.children.map((node) {
    return switch (node) {
      LibraryBook b when b.relativePath == relativePath => update(b),
      LibraryFolder f => _replaceBook(f, relativePath, update),
      _ => node,
    };
  }).toList();
  return folder.copyWith(children: newChildren);
}
```

Also add `fb2MetadataWriterProvider` to `providers.dart`:
```dart
import 'package:opds_browser/data/fb2_metadata_writer.dart';

final fb2MetadataWriterProvider = Provider<Fb2MetadataWriter>(
  (ref) => Fb2MetadataWriter(),
);
```

And add import in `local_library_screen.dart`:
```dart
import 'package:opds_browser/data/fb2_metadata_writer.dart';
```

- [ ] **Step 4: Run test — expect PASS**

```powershell
flutter test test/ui/local_library_notifier_test.dart
```

---

### Task 3: Edit metadata bottom sheet UI

**Files:**
- Create: `lib/ui/widgets/edit_book_metadata_sheet.dart`
- Modify: `lib/ui/local_library_screen.dart` — wire `_BookTile` tap → sheet

- [ ] **Step 1: Create `lib/ui/widgets/edit_book_metadata_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/ui/local_library_screen.dart';
import 'package:opds_browser/ui/providers.dart';

class EditBookMetadataSheet extends ConsumerStatefulWidget {
  const EditBookMetadataSheet({required this.book, super.key});
  final LibraryBook book;

  @override
  ConsumerState<EditBookMetadataSheet> createState() => _EditBookMetadataSheetState();
}

class _EditBookMetadataSheetState extends ConsumerState<EditBookMetadataSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _seriesCtrl;
  late final TextEditingController _seriesIndexCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final meta = widget.book.meta;
    _titleCtrl = TextEditingController(text: meta.title);
    _authorCtrl = TextEditingController(text: meta.author);
    _seriesCtrl = TextEditingController(text: meta.series ?? '');
    _seriesIndexCtrl = TextEditingController(
      text: meta.seriesIndex?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _seriesCtrl.dispose();
    _seriesIndexCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final seriesText = _seriesCtrl.text.trim();
      final seriesIndexText = _seriesIndexCtrl.text.trim();
      final newMeta = LocalBookMetadata(
        title: _titleCtrl.text.trim(),
        author: _authorCtrl.text.trim(),
        series: seriesText.isEmpty ? null : seriesText,
        seriesIndex: seriesText.isNotEmpty && seriesIndexText.isNotEmpty
            ? int.tryParse(seriesIndexText)
            : null,
      );
      await ref
          .read(localLibraryNotifierProvider.notifier)
          .updateBook(widget.book, newMeta);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSeries = _seriesCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit book', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _authorCtrl,
              decoration: const InputDecoration(
                labelText: 'Author',
                helperText: 'Comma-separated for multiple authors',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _seriesCtrl,
              decoration: const InputDecoration(labelText: 'Series (optional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _seriesIndexCtrl,
              decoration: const InputDecoration(labelText: 'Series # (optional)'),
              enabled: hasSeries,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire `_BookTile` tap to open the sheet in `lib/ui/local_library_screen.dart`**

Update `_BookTile.build()` — add `onTap` to `ListTile`:

```dart
// In _BookTile.build(), update ListTile to add onTap:
child: ListTile(
  onTap: () => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EditBookMetadataSheet(book: book),
  ),
  leading: const Icon(Icons.book),
  // ... rest unchanged
),
```

Also add import to `local_library_screen.dart`:
```dart
import 'package:opds_browser/ui/widgets/edit_book_metadata_sheet.dart';
```

- [ ] **Step 3: Run `dart run tool/check.dart`** — must be clean

- [ ] **Step 4: Commit**

```powershell
git add lib/ui/widgets/edit_book_metadata_sheet.dart lib/ui/local_library_screen.dart lib/ui/providers.dart test/ui/local_library_notifier_test.dart
git commit -m "feat: add edit book metadata dialog (Step 2)"
```

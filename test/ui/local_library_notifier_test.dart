import 'dart:convert';
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

class FakeReadWriter implements LocalBookReadWriter {
  final _callLog = <String>[];
  List<String> get writtenPaths => _callLog;

  // Returns minimal valid FB2 so patchBytes succeeds in updateBook tests.
  static const _minimalFb2 =
      '<?xml version="1.0"?>'
      '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
      '<description><title-info>'
      '<author><last-name>Old</last-name></author>'
      '<book-title>Old</book-title>'
      '</title-info></description>'
      '<body><section><p/></section></body>'
      '</FictionBook>';

  final bool returnValidFb2;

  FakeReadWriter({this.returnValidFb2 = false});

  @override
  Future<Uint8List> readBytes(String documentUri) async {
    if (returnValidFb2) {
      return Uint8List.fromList(utf8.encode(_minimalFb2));
    }
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
    _callLog.add(documentUri);
  }
}

// ── Test helper ───────────────────────────────────────────────────────────────

ProviderContainer _makeContainer({
  required List<LibraryFile> files,
  SqfliteLocalLibraryCache? cache,
  LocalBookReadWriter? readWriter,
}) {
  final db = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
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

  test(
    'cache hit avoids re-parsing — parser not called for cached file',
    () async {
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final cache = SqfliteLocalLibraryCache(db);
      await cache.put(
        'Jane Doe/book.fb2',
        const LocalBookMetadata(title: 'Cached Title', author: 'Cached Author'),
      );

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
    },
  );

  test('refresh clears cache and rescans', () async {
    final db = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final cache = SqfliteLocalLibraryCache(db);
    await cache.put(
      'Jane Doe/book.fb2',
      const LocalBookMetadata(title: 'Old Cache', author: 'X'),
    );

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
    // book gets placeholder metadata which is now cached as fallback
    final cached = await cache.get('Jane Doe/book.fb2');
    expect(cached, isNotNull);
    expect(cached?.title, 'book.fb2');
  });

  test('validationRun starts as false', () async {
    final c = _makeContainer(files: []);
    addTearDown(c.dispose);
    await c.read(localLibraryNotifierProvider.notifier).waitForReady();
    final state = c.read(localLibraryNotifierProvider) as LibraryReady;
    expect(state.validationRun, isFalse);
  });

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
      // Pre-populate cache so the initial scan picks up the matching author.
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final cache = SqfliteLocalLibraryCache(db);
      await cache.put(
        'Jane Doe/book.fb2',
        const LocalBookMetadata(title: 'T', author: 'Jane Doe'),
      );
      final c = _makeContainer(files: [file], cache: cache);
      addTearDown(c.dispose);
      await c.read(localLibraryNotifierProvider.notifier).waitForReady();

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
      final rw = FakeReadWriter(returnValidFb2: true);
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

  group('updateBook', () {
    test('updates in-memory book meta and cache', () async {
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final cache = SqfliteLocalLibraryCache(db);
      final rw = FakeReadWriter(returnValidFb2: true);

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

      const newMeta = LocalBookMetadata(
        title: 'New Title',
        author: 'New Author',
      );
      await c
          .read(localLibraryNotifierProvider.notifier)
          .updateBook(book, newMeta);

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
}

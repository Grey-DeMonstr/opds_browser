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

// ── Test helper ───────────────────────────────────────────────────────────────

ProviderContainer _makeContainer({
  required List<LibraryFile> files,
  SqfliteLocalLibraryCache? cache,
}) {
  final db = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
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
}

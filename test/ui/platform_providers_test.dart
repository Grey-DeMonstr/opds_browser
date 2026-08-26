@TestOn('!android')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/file_system_book_read_writer.dart';
import 'package:opds_browser/data/file_system_local_library_scanner.dart';
import 'package:opds_browser/ui/providers.dart';

/// The desktop builds have no SAF and no Android intents. Every provider that
/// reaches the platform has to pick the plain file-system implementation there,
/// or the screen behind it dies with a missing-plugin error.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('local library scanner reads the file system off Android', () {
    expect(
      container.read(localLibraryScannerProvider),
      isA<FileSystemLocalLibraryScanner>(),
    );
  });

  test('book read/writer uses the file system off Android', () {
    expect(
      container.read(localBookReadWriterProvider),
      isA<FileSystemBookReadWriter>(),
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/file_system_download_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late FileSystemDownloadStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_dl_storage_test');
    storage = FileSystemDownloadStorage(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('exists returns false for missing file', () async {
    expect(await storage.exists(<String>[], 'missing.epub'), isFalse);
  });

  test('exists returns true after write', () async {
    final file = File(p.join(tempDir.path, 'book.epub'));
    await file.writeAsBytes([1, 2, 3]);
    expect(await storage.exists(<String>[], 'book.epub'), isTrue);
  });

  test('write saves bytes and returns absolute path', () async {
    final result = await storage.write(
      <String>[],
      'book.epub',
      Stream<List<int>>.value([1, 2, 3]),
      'application/epub+zip',
    );
    expect(p.isAbsolute(result), isTrue);
    expect(await File(result).readAsBytes(), equals([1, 2, 3]));
  });

  test('write creates intermediate path segments as directories', () async {
    await storage.write(
      ['Author', 'Series'],
      'book.epub',
      Stream<List<int>>.value([42]),
      'application/epub+zip',
    );
    final file = File(p.join(tempDir.path, 'Author', 'Series', 'book.epub'));
    expect(await file.exists(), isTrue);
  });

  test('exists with path segments mirrors write location', () async {
    await storage.write(
      ['A', 'B'],
      'x.epub',
      Stream<List<int>>.value([1]),
      'application/epub+zip',
    );
    expect(await storage.exists(['A', 'B'], 'x.epub'), isTrue);
    expect(await storage.exists(<String>[], 'x.epub'), isFalse);
  });
}

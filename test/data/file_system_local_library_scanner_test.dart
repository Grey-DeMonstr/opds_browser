import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/file_system_local_library_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late FileSystemLocalLibraryScanner scanner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_lib_scanner_test');
    scanner = const FileSystemLocalLibraryScanner();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> writeFile(List<String> segments) async {
    final file = File(p.joinAll([tempDir.path, ...segments]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1]);
  }

  test('finds .fb2 and .fb2.zip files, ignoring other extensions', () async {
    await writeFile(['a.fb2']);
    await writeFile(['b.fb2.zip']);
    await writeFile(['cover.jpg']);
    await writeFile(['notes.txt']);

    final files = await scanner.scan(tempDir.path).toList();

    expect(
      files.map((f) => f.relativePath).toSet(),
      equals({'a.fb2', 'b.fb2.zip'}),
    );
  });

  test(
    'recurses into subfolders and joins paths with a forward slash',
    () async {
      await writeFile(['Jane Doe', 'Series', 'book.fb2']);

      final files = await scanner.scan(tempDir.path).toList();

      expect(files, hasLength(1));
      expect(files.single.relativePath, 'Jane Doe/Series/book.fb2');
    },
  );

  test('reports the file path and its parent folder path', () async {
    await writeFile(['Jane Doe', 'book.fb2']);

    final file = (await scanner.scan(tempDir.path).toList()).single;

    expect(file.documentUri, p.join(tempDir.path, 'Jane Doe', 'book.fb2'));
    expect(file.parentUri, p.join(tempDir.path, 'Jane Doe'));
    expect(File(file.documentUri).existsSync(), isTrue);
  });

  test('matches extensions case-insensitively', () async {
    await writeFile(['LOUD.FB2']);
    await writeFile(['Mixed.Fb2.Zip']);

    final files = await scanner.scan(tempDir.path).toList();

    expect(files, hasLength(2));
  });

  test('yields nothing for a folder that does not exist', () async {
    final files = await scanner.scan(p.join(tempDir.path, 'nope')).toList();

    expect(files, isEmpty);
  });
}

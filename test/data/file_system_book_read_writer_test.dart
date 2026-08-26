import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/file_system_book_read_writer.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late FileSystemBookReadWriter readWriter;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_book_rw_test');
    readWriter = const FileSystemBookReadWriter();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('readBytes returns the file contents', () async {
    final path = p.join(tempDir.path, 'book.fb2');
    await File(path).writeAsBytes([1, 2, 3]);

    expect(await readWriter.readBytes(path), equals([1, 2, 3]));
  });

  test('writeBytes overwrites the file in place', () async {
    final path = p.join(tempDir.path, 'book.fb2');
    await File(path).writeAsBytes([1, 2, 3]);

    await readWriter.writeBytes(
      path,
      tempDir.path,
      'book.fb2',
      'application/x-fictionbook+xml',
      Uint8List.fromList([9, 9]),
    );

    expect(await File(path).readAsBytes(), equals([9, 9]));
  });

  test('writeBytes creates the file when it is missing', () async {
    await readWriter.writeBytes(
      p.join(tempDir.path, 'new.fb2'),
      tempDir.path,
      'new.fb2',
      'application/x-fictionbook+xml',
      Uint8List.fromList([7]),
    );

    expect(await File(p.join(tempDir.path, 'new.fb2')).readAsBytes(), [7]);
  });
}

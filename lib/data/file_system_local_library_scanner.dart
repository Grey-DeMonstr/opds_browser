import 'dart:io';

import 'package:opds_browser/domain/local_library.dart';
import 'package:path/path.dart' as p;

/// Walks a plain directory tree — what the desktop builds get instead of SAF.
///
/// The `documentUri` / `parentUri` it reports are ordinary file paths, which is
/// exactly what the file-system read/writer and download storage expect on
/// those platforms.
class FileSystemLocalLibraryScanner implements LocalLibraryScanner {
  const FileSystemLocalLibraryScanner();

  @override
  Stream<LibraryFile> scan(String treeUri) => _scanDirectory(treeUri, '');

  Stream<LibraryFile> _scanDirectory(String dirPath, String prefix) async* {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final children = await dir.list(followLinks: false).toList();
    children.sort((a, b) => a.path.compareTo(b.path));

    for (final child in children) {
      final name = p.basename(child.path);
      final relPath = prefix.isEmpty ? name : '$prefix/$name';
      if (child is Directory) {
        yield* _scanDirectory(child.path, relPath);
      } else if (child is File && _isBook(name)) {
        yield LibraryFile(
          relativePath: relPath,
          documentUri: child.path,
          parentUri: dirPath,
        );
      }
    }
  }

  bool _isBook(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.fb2') || lower.endsWith('.fb2.zip');
  }
}

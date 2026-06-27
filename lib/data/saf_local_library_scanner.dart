import 'package:opds_browser/domain/local_library.dart';
import 'package:saf_util/saf_util.dart';

class SafLocalLibraryScanner implements LocalLibraryScanner {
  @override
  Stream<LibraryFile> scan(String treeUri) =>
      _scanDirectory(treeUri, treeUri, '');

  Stream<LibraryFile> _scanDirectory(
    String treeUri,
    String dirUri,
    String prefix,
  ) async* {
    final children = await SafUtil().list(dirUri);
    for (final child in children) {
      if (child.isDir) {
        final childPrefix = prefix.isEmpty
            ? child.name
            : '$prefix/${child.name}';
        yield* _scanDirectory(treeUri, child.uri, childPrefix);
      } else {
        final nameLower = child.name.toLowerCase();
        if (nameLower.endsWith('.fb2') || nameLower.endsWith('.fb2.zip')) {
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

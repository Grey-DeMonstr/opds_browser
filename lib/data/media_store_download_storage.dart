import 'dart:io';
import 'dart:typed_data';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:opds_browser/domain/repositories.dart';

class MediaStoreDownloadStorage implements DownloadStorage {
  // MediaStore.appFolder must be non-empty — this value passes the guard.
  // Actual file placement is controlled via explicit relativePath in each call.
  static const _appFolder = 'OPDS Browser';

  final _store = MediaStore();

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) {
    _ensureAppFolder();
    return _store.isFileExist(
      fileName: fileName,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath:
          pathSegments.isEmpty ? FilePath.root : pathSegments.join('/'),
    );
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    _ensureAppFolder();
    final data = await bytes.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final tempFile = File('${Directory.systemTemp.path}/$fileName');
    await tempFile.writeAsBytes(Uint8List.fromList(data));
    try {
      final info = await _store.saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath:
            pathSegments.isEmpty ? FilePath.root : pathSegments.join('/'),
      );
      return info?.uri.toString() ?? '';
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  void _ensureAppFolder() {
    if (MediaStore.appFolder.isEmpty) {
      MediaStore.appFolder = _appFolder;
    }
  }
}

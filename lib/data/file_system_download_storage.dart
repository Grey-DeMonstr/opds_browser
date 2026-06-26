import 'dart:io';

import 'package:opds_browser/domain/repositories.dart';
import 'package:path/path.dart' as p;

class FileSystemDownloadStorage implements DownloadStorage {
  const FileSystemDownloadStorage(this._basePath);

  final String _basePath;

  static FileSystemDownloadStorage downloads() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return FileSystemDownloadStorage(p.join(home, 'Downloads'));
  }

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) {
    return File(_resolve(pathSegments, fileName)).exists();
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
    String mimeType,
  ) async {
    final file = File(_resolve(pathSegments, fileName));
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    await sink.addStream(bytes);
    await sink.close();
    return file.path;
  }

  String _resolve(List<String> pathSegments, String fileName) =>
      p.joinAll([_basePath, ...pathSegments, fileName]);
}

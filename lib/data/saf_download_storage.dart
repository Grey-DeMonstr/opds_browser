import 'dart:typed_data';

import 'package:opds_browser/domain/repositories.dart';
// ignore: implementation_imports
import 'package:saf/src/storage_access_framework/api.dart' as saf_api;
// ignore: implementation_imports
import 'package:saf/src/storage_access_framework/document_file.dart';

class SafDownloadStorage implements DownloadStorage {
  final String _treeUriString;
  SafDownloadStorage(this._treeUriString);

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async {
    var dir = await DocumentFile.fromTreeUri(Uri.parse(_treeUriString));
    if (dir == null) return false;
    for (final segment in pathSegments) {
      dir = await saf_api.findFile(dir!.uri, segment);
      if (dir == null) return false;
    }
    return await saf_api.findFile(dir!.uri, fileName) != null;
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    var dir = await DocumentFile.fromTreeUri(Uri.parse(_treeUriString));
    for (final segment in pathSegments) {
      final current = dir!;
      final existing = await saf_api.findFile(current.uri, segment);
      dir = existing ?? await saf_api.createDirectory(current.uri, segment);
    }
    final buffer = await bytes.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final file = await saf_api.createFileAsBytes(
      dir!.uri,
      mimeType: 'application/octet-stream',
      displayName: fileName,
      content: Uint8List.fromList(buffer),
    );
    return file!.uri.toString();
  }
}

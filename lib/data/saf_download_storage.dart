import 'dart:typed_data';

import 'package:opds_browser/domain/repositories.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

class SafDownloadStorage implements DownloadStorage {
  final String _treeUriString;
  SafDownloadStorage(this._treeUriString);

  final _safUtil = SafUtil();
  final _safStream = SafStream();

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async {
    final file = await _safUtil.child(_treeUriString, [
      ...pathSegments,
      fileName,
    ]);
    return file != null;
  }

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
    String mimeType,
  ) async {
    var dirUri = _treeUriString;
    if (pathSegments.isNotEmpty) {
      final dir = await _safUtil.mkdirp(_treeUriString, pathSegments);
      dirUri = dir.uri;
    }
    final buffer = await bytes.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final result = await _safStream.writeFileBytes(
      dirUri,
      fileName,
      mimeType,
      Uint8List.fromList(buffer),
    );
    return result.uri.toString();
  }
}

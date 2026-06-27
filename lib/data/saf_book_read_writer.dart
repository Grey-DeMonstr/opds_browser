import 'dart:typed_data';

import 'package:opds_browser/domain/local_library.dart';
import 'package:saf_stream/saf_stream.dart';

class SafBookReadWriter implements LocalBookReadWriter {
  final _safStream = SafStream();

  @override
  Future<Uint8List> readBytes(String documentUri) =>
      _safStream.readFileBytes(documentUri);

  @override
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    await _safStream.writeFileBytes(
      parentUri,
      fileName,
      mimeType,
      bytes,
      overwrite: true,
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:opds_browser/domain/local_library.dart';

/// Reads and rewrites books straight through `dart:io`, for the platforms that
/// address the library by path rather than by SAF document URI.
class FileSystemBookReadWriter implements LocalBookReadWriter {
  const FileSystemBookReadWriter();

  @override
  Future<Uint8List> readBytes(String documentUri) =>
      File(documentUri).readAsBytes();

  @override
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    await File(documentUri).writeAsBytes(bytes, flush: true);
  }
}

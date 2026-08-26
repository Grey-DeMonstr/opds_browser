import 'package:flutter/services.dart';
import 'package:opds_browser/domain/repositories.dart';

const _channel = MethodChannel('monster.greyde.opds_browser/open_file');

/// Hands a downloaded book to Android through an `ACTION_VIEW` intent.
class AndroidFileOpener implements FileOpener {
  const AndroidFileOpener();

  @override
  Future<void> open(String uri, String mimeType) async {
    await _channel.invokeMethod<void>('openFile', {
      'uri': uri,
      'mimeType': mimeType,
    });
  }
}

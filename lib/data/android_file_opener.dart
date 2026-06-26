import 'package:flutter/services.dart';

const _channel = MethodChannel('monster.greyde.opds_browser/open_file');

Future<void> openFile(String contentUri, String mimeType) async {
  await _channel.invokeMethod<void>('openFile', {
    'uri': contentUri,
    'mimeType': mimeType,
  });
}

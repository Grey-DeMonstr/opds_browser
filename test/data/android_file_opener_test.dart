import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/android_file_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('monster.greyde.opds_browser/open_file');
  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('openFile sends correct uri and mimeType to native channel', () async {
    await openFile('content://test/document/1', 'application/epub+zip');

    expect(log, hasLength(1));
    expect(log.first.method, 'openFile');
    expect(log.first.arguments['uri'], 'content://test/document/1');
    expect(log.first.arguments['mimeType'], 'application/epub+zip');
  });

  test('openFile with different mimeType passes it through unchanged', () async {
    await openFile('content://test/document/2', 'application/pdf');

    expect(log.first.arguments['mimeType'], 'application/pdf');
  });
}

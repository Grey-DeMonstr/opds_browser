import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/desktop_file_opener.dart';

void main() {
  late List<(String, List<String>)> calls;
  late ProcessResult result;

  setUp(() {
    calls = [];
    result = ProcessResult(1, 0, '', '');
  });

  DesktopFileOpener openerFor(String os) => DesktopFileOpener(
    operatingSystem: os,
    runProcess: (executable, arguments) async {
      calls.add((executable, arguments));
      return result;
    },
  );

  test('hands the file to the Windows shell', () async {
    await openerFor('windows').open(r'C:\Books\a.fb2', 'application/xml');

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'cmd');
    expect(calls.single.$2, ['/c', 'start', '', r'C:\Books\a.fb2']);
  });

  test('hands the file to the macOS shell', () async {
    await openerFor('macos').open('/books/a.fb2', 'application/xml');

    expect(calls.single.$1, 'open');
    expect(calls.single.$2, ['/books/a.fb2']);
  });

  test('hands the file to the Linux shell', () async {
    await openerFor('linux').open('/books/a.fb2', 'application/xml');

    expect(calls.single.$1, 'xdg-open');
    expect(calls.single.$2, ['/books/a.fb2']);
  });

  test('throws when the shell reports a failure', () async {
    result = ProcessResult(1, 1, '', 'no application knows this file');

    expect(
      () => openerFor('windows').open('a.fb2', 'application/xml'),
      throwsA(isA<FileOpenException>()),
    );
  });

  test('throws for a platform with no known open command', () async {
    expect(
      () => openerFor('fuchsia').open('a.fb2', 'application/xml'),
      throwsA(isA<FileOpenException>()),
    );
    expect(calls, isEmpty);
  });
}

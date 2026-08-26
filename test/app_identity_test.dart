import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app's identity has to read the same on every platform it ships to.
///
/// On Windows it is not cosmetic: `path_provider` builds the settings folder
/// out of the executable's CompanyName and ProductName, so a stray
/// `com.example` there parks the app's preferences in a folder shared with
/// every other unedited Flutter app on the machine. `flutter create .` puts
/// that default back, which is how it got there the first time.
const _applicationId = 'monster.greyde.opds_browser';

String _rcValue(String source, String key) {
  final match = RegExp(
    r'VALUE\s+"' + key + r'",\s*"([^"]*)"',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'Runner.rc has no $key entry');
  return match!.group(1)!;
}

void main() {
  test('Android declares the expected application id and namespace', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('applicationId = "$_applicationId"'));
    expect(gradle, contains('namespace = "$_applicationId"'));
  });

  test('Windows resources spell out the same identity', () {
    final rc = File('windows/runner/Runner.rc').readAsStringSync();

    final company = _rcValue(rc, 'CompanyName');
    final product = _rcValue(rc, 'ProductName');

    expect('$company.$product', _applicationId);
  });

  test('Windows resources carry none of the Flutter template defaults', () {
    final rc = File('windows/runner/Runner.rc').readAsStringSync();

    expect(rc, isNot(contains('com.example')));
  });
}

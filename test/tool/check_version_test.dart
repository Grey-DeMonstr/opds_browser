import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_version.dart';

const _pubspecWithBuild = '''
name: opds_browser
description: "A new Flutter project."
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.12.1
''';

const _pubspecWithoutBuild = '''
name: opds_browser
version: 0.1.0

environment:
  sdk: ^3.12.1
''';

const _pubspecNoVersion = '''
name: opds_browser

environment:
  sdk: ^3.12.1
''';

void main() {
  group('resolveVersion', () {
    test('accepts a tag matching a pubspec version with a +build suffix', () {
      final result = resolveVersion('v0.1.0', _pubspecWithBuild);
      expect(result, isA<VersionAgreed>());
      expect((result as VersionAgreed).version, '0.1.0');
    });

    test(
      'accepts a tag matching a pubspec version without a +build suffix',
      () {
        final result = resolveVersion('v0.1.0', _pubspecWithoutBuild);
        expect(result, isA<VersionAgreed>());
        expect((result as VersionAgreed).version, '0.1.0');
      },
    );

    test('rejects a tag whose version differs from pubspec', () {
      final result = resolveVersion('v0.2.0', _pubspecWithBuild);
      expect(result, isA<VersionRejected>());
      expect((result as VersionRejected).message, contains('0.2.0'));
      expect(result.message, contains('0.1.0'));
    });

    test('rejects a tag missing the v prefix', () {
      final result = resolveVersion('0.1.0', _pubspecWithBuild);
      expect(result, isA<VersionRejected>());
      expect((result as VersionRejected).message, contains('vX.Y.Z'));
    });

    test('rejects a malformed tag', () {
      final result = resolveVersion('v1.2', _pubspecWithBuild);
      expect(result, isA<VersionRejected>());
      expect((result as VersionRejected).message, contains('vX.Y.Z'));
    });

    test('rejects a tag with a suffix after the patch number', () {
      final result = resolveVersion('v0.1.0-rc1', _pubspecWithBuild);
      expect(result, isA<VersionRejected>());
      expect((result as VersionRejected).message, contains('vX.Y.Z'));
    });

    test('rejects a pubspec with no version key', () {
      final result = resolveVersion('v0.1.0', _pubspecNoVersion);
      expect(result, isA<VersionRejected>());
      expect((result as VersionRejected).message, contains('version:'));
    });

    test('ignores an indented version key from a nested block', () {
      const pubspec = '''
name: opds_browser
dependencies:
  something:
    version: 9.9.9
''';
      final result = resolveVersion('v9.9.9', pubspec);
      expect(result, isA<VersionRejected>());
      expect((result as VersionRejected).message, contains('version:'));
    });

    test('tolerates surrounding whitespace on the tag', () {
      final result = resolveVersion('  v0.1.0\n', _pubspecWithBuild);
      expect(result, isA<VersionAgreed>());
    });
  });
}

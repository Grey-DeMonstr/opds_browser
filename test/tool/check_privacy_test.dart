import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_privacy.dart';

/// The working-tree sweep is deliberately local-only: it shells out to
/// `git ls-files` and reads the checkout, which is a developer's pre-commit
/// concern rather than something to re-litigate on every push.
final String? _localOnly = Platform.environment.containsKey('CI')
    ? 'working-tree sweep runs locally, not on CI'
    : null;

List<String> _values(String contents) =>
    findPrivateData(contents).map((PrivacyFinding f) => f.value).toList();

void main() {
  group('hosts', () {
    test('flags an unknown host in a URL', () {
      final findings = findPrivateData(
        'const url = "https://catalogue.private-server.ru/opds";',
      );
      expect(findings, hasLength(1));
      expect(findings.single.kind, PrivacyFindingKind.host);
      expect(findings.single.value, 'catalogue.private-server.ru');
    });

    test('flags an unknown host mentioned bare, outside a URL', () {
      expect(_values('/// as `catalogue.private-server.ru` publishes them'), [
        'catalogue.private-server.ru',
      ]);
    });

    test('matches hosts case-insensitively', () {
      expect(_values('CATALOGUE.PRIVATE-SERVER.RU'), [
        'catalogue.private-server.ru',
      ]);
    });

    test('reports a host in a URL once, not twice', () {
      expect(
        findPrivateData('https://catalogue.private-server.ru/opds'),
        hasLength(1),
      );
    });

    test('allows an allow-listed third-party host', () {
      expect(_values('https://www.gutenberg.org/ebooks.opds'), isEmpty);
      expect(_values('see https://opds-spec.org/ for the profile'), isEmpty);
    });

    test('allows RFC 2606 / 6761 reserved names and their subdomains', () {
      expect(_values('https://example.com/a https://example.org/b'), isEmpty);
      expect(_values('https://library.example.com/opds'), isEmpty);
      expect(_values('https://opds.example.org/opds'), isEmpty);
      expect(_values('http://x.test/feed and other.example'), isEmpty);
      expect(_values('https://nope.invalid/'), isEmpty);
    });

    test('ignores single-label hosts, which identify nobody', () {
      expect(_values('http://localhost:8080/opds and http://host/x'), isEmpty);
    });

    test('does not mistake file names for hosts', () {
      expect(
        _values('README.md pubspec.yaml build.gradle.kts app_database.dart'),
        isEmpty,
      );
    });

    test('does not mistake reverse-DNS identifiers for hosts', () {
      expect(
        _values('monster.greyde.opds_browser com.example androidx.core'),
        isEmpty,
      );
    });
  });

  group('IP addresses', () {
    test('flags a LAN address', () {
      final findings = findPrivateData('http://192.168.0.42:8080/opds');
      expect(findings, hasLength(1));
      expect(findings.single.kind, PrivacyFindingKind.ipAddress);
      expect(findings.single.value, '192.168.0.42');
    });

    test('allows RFC 5737 documentation addresses', () {
      expect(_values('http://192.0.2.10:8080/opds'), isEmpty);
      expect(_values('198.51.100.7 and 203.0.113.9'), isEmpty);
    });

    test('allows loopback and the unspecified address', () {
      expect(_values('127.0.0.1 and 0.0.0.0'), isEmpty);
    });

    test('ignores dotted numbers that are not addresses', () {
      expect(_values('version 3.44.1 and 1.2.3.4.5 and 999.1.2.3'), isEmpty);
    });
  });

  group('filesystem paths', () {
    test('flags a Windows drive path', () {
      final findings = findPrivateData(r'the repo lives on Z:\work\project');
      expect(findings, hasLength(1));
      expect(findings.single.kind, PrivacyFindingKind.filesystemPath);
      expect(findings.single.value, r'Z:\work\project');
    });

    test('flags a forward-slash drive path', () {
      expect(_values('Z:/work/project'), ['Z:/work/project']);
    });

    test('flags POSIX home and mount paths', () {
      expect(_values('/home/someone/projects'), ['/home/someone/projects']);
      expect(_values('/Users/someone/projects'), ['/Users/someone/projects']);
      expect(_values('/mnt/z/work'), ['/mnt/z/work']);
    });

    test('does not mistake a URL scheme for a drive path', () {
      expect(_values('https://opds-spec.org/x'), isEmpty);
    });

    test('allows a placeholder that names no real directory', () {
      expect(_values('the repo lives on `<project root>`'), isEmpty);
      expect(_values(r'the WSL2 <-> `/mnt/<drive>` penalty'), isEmpty);
    });

    test('allows generic roots that identify nobody', () {
      expect(_values('/tmp/cache and /data/user/0/x'), isEmpty);
    });

    test('allows an allow-listed synthetic path', () {
      expect(_values(r"openerFor('windows').open(r'C:\Books\a.fb2')"), isEmpty);
    });
  });

  group('findings', () {
    test('returns nothing for clean content', () {
      expect(findPrivateData('void main() {}\n'), isEmpty);
    });

    test('reports the 1-based line of each finding', () {
      final findings = findPrivateData(
        'clean\nhttps://catalogue.private-server.ru/x\nclean\n192.168.0.42\n',
      );
      expect(findings.map((PrivacyFinding f) => f.line), [2, 4]);
    });
  });

  group('the working tree', () {
    test('holds no private data in any tracked file', () async {
      final scan = await scanTrackedFiles();
      expect(
        scan.report,
        isEmpty,
        reason:
            'Tracked files contain data that must not be committed. If one of '
            'these is a genuinely public host or a synthetic path, add it to '
            'allowedHosts or allowedPaths in tool/check_privacy.dart.',
      );
      expect(scan.scanned, greaterThan(0));
    }, skip: _localOnly);
  });
}

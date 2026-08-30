/// Guards the repository against committing anything that identifies the
/// machine it is developed on or the private catalogues it is developed
/// against: hostnames, IP addresses and absolute filesystem paths.
///
/// Usage: `dart run tool/check_privacy.dart`
///
/// Every rule here is an ALLOW-list, on purpose. A deny-list would have to
/// spell out the very strings we are trying to keep out of the repository,
/// which would put them straight back into it. So anything the scanner does
/// not recognise is reported, and a genuinely new third-party host has to be
/// added to [allowedHosts] deliberately, in review, before it can land.
///
/// All the logic lives in [findPrivateData] so it can be unit tested without
/// touching the filesystem; [scanRepository] and `main` only do I/O.
library;

import 'dart:convert';
import 'dart:io';

/// Hosts that may appear in the repository.
///
/// New tests should prefer the reserved names accepted by [_isReservedName]
/// (`example.com`, anything under `.test` or `.invalid`) over inventing another
/// synthetic domain to add here.
const Set<String> allowedHosts = {
  // Open catalogues and the OPDS ecosystem.
  'calibre.kovidgoyal.net',
  'gutenberg.org',
  'opds-spec.org',
  'standardebooks.org',
  'www.gutenberg.org',

  // Specifications and schemas referenced by the parser and the manifests.
  'a9.com',
  'android.net',
  'java.io',
  'purl.org',
  'schemas.android.com',
  'schemas.microsoft.com',
  'www.w3.org',

  // Toolchain and documentation.
  'dart.dev',
  'services.gradle.org',
  'developer.android.com',
  'developer.mozilla.org',
  'docs.flutter.dev',
  'docs.microsoft.com',
  'flutter.dev',
  'github.com',
  'pub.dev',
  'scripts.sil.org',

  // Licence texts.
  'fsf.org',
  'www.gnu.org',

  // Third-party strings carried inside committed feed fixtures. These come
  // with the book blurbs the fixtures capture; they are nobody's private data.
  'en.wikipedia.org',
  'www.belorya-rpg.ru',
  'www.gribuser.ru',

  // Synthetic names existing tests are written against.
  'a.com',
  'b.com',
  'delete.me',
  'doomed.com',
  'e.org',
  'first.com',
  'keep.com',
  'original.com',
  'other.com',
  'parent.com',
  'second.com',
  'updated.com',
  'x.com',
};

/// Absolute paths that may appear in the repository: synthetic values that
/// have to look like a real path for the code under test to be exercised.
const Set<String> allowedPaths = {
  // Feeds the Windows branch of the desktop file opener.
  r'C:\Books\a.fb2',
};

/// Files exempt from the scan.
const Set<String> exemptPaths = {
  // The scanner's own test data is, by design, made of strings it must reject.
  'test/tool/check_privacy_test.dart',
};

/// Last labels that mark a bare token as a hostname rather than a file name or
/// a reverse-DNS identifier. Deliberately omits TLDs that double as file
/// extensions (`md`, `sh`) or as package-name tails (`app`).
const Set<String> _networkTlds = {
  'ac',
  'au',
  'br',
  'by',
  'ca',
  'cc',
  'cn',
  'co',
  'com',
  'cz',
  'de',
  'dev',
  'es',
  'eu',
  'fi',
  'fr',
  'in',
  'info',
  'io',
  'it',
  'jp',
  'me',
  'net',
  'nl',
  'no',
  'nz',
  'org',
  'pl',
  'ru',
  'se',
  'tv',
  'ua',
  'uk',
  'us',
  'xyz',
};

/// Roots under which an absolute path names somebody's own machine.
/// Generic roots such as `/tmp` or Android's `/data` identify nobody.
const String _personalRoots = 'home|Users|users|mnt|media|root';

/// The host of an `http(s)` URL, without any `:port`.
final RegExp _urlHost = RegExp(r'https?://([A-Za-z0-9._-]+)');

/// A dotted hostname written outside a URL. The lookbehind keeps it from
/// matching the tail of an identifier such as `app_database.dart`.
final RegExp _bareHost = RegExp(
  r'(?<![\w.-])[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+(?![\w-])',
);

/// A dotted quad, not part of a longer dotted run such as `1.2.3.4.5`.
final RegExp _ipv4 = RegExp(r'(?<![\w.])\d{1,3}(?:\.\d{1,3}){3}(?![\w.])');

/// A Windows drive path, in either slash direction. The lookbehind keeps the
/// `s:` of `https://` from reading as a drive letter.
final RegExp _drivePath = RegExp(
  r'(?<![A-Za-z0-9])[A-Za-z]:[\\/][A-Za-z0-9_.\\/-]+',
);

/// `/home/<user>/...` and friends. The lookbehind keeps it from matching the
/// path part of a URL such as `https://example.com/home/x`.
final RegExp _homePath = RegExp(
  '(?<![A-Za-z0-9])/(?:$_personalRoots)/[A-Za-z0-9_.-][A-Za-z0-9_./-]*',
);

/// What kind of private data a [PrivacyFinding] describes.
enum PrivacyFindingKind {
  host('host'),
  ipAddress('IP address'),
  filesystemPath('filesystem path');

  const PrivacyFindingKind(this.label);

  /// How the kind is named in the report.
  final String label;
}

/// Something the scanner will not allow into the repository.
final class PrivacyFinding {
  const PrivacyFinding({
    required this.line,
    required this.kind,
    required this.value,
  });

  /// 1-based line the value was first seen on.
  final int line;
  final PrivacyFindingKind kind;

  /// The offending text, lower-cased for hosts.
  final String value;
}

/// True for names RFC 2606 and RFC 6761 reserve for documentation and tests,
/// which can never belong to anyone.
bool _isReservedName(String host) {
  for (final suffix in const ['.example', '.test', '.invalid', '.localhost']) {
    if (host.endsWith(suffix)) return true;
  }
  for (final name in const ['example.com', 'example.org', 'example.net']) {
    if (host == name || host.endsWith('.$name')) return true;
  }
  return false;
}

/// True when every label of [text] is a number in 0..255.
bool _isIpv4Literal(String text) {
  final parts = text.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return false;
  }
  return true;
}

/// True for addresses that cannot point at anybody's machine: the RFC 5737
/// documentation ranges, loopback, and the unspecified address.
bool _isAllowedIp(String address) =>
    address.startsWith('192.0.2.') ||
    address.startsWith('198.51.100.') ||
    address.startsWith('203.0.113.') ||
    address.startsWith('127.') ||
    address == '0.0.0.0';

bool _isAllowedHost(String host) {
  // A single label names no domain, so it identifies nobody.
  if (!host.contains('.')) return true;
  // Addresses are the IP rule's business, not the host rule's.
  if (_isIpv4Literal(host)) return true;
  return allowedHosts.contains(host) || _isReservedName(host);
}

/// Reports every piece of private data in [contents].
///
/// Each distinct value is reported once, against the first line it appears on.
List<PrivacyFinding> findPrivateData(String contents) {
  final findings = <PrivacyFinding>[];
  final seen = <String>{};
  final lines = contents.split('\n');

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final lowered = line.toLowerCase();

    void report(PrivacyFindingKind kind, String value) {
      if (seen.add('${kind.name}\u0000$value')) {
        findings.add(PrivacyFinding(line: index + 1, kind: kind, value: value));
      }
    }

    for (final match in _urlHost.allMatches(line)) {
      final host = match.group(1)!.toLowerCase();
      if (!_isAllowedHost(host)) report(PrivacyFindingKind.host, host);
    }

    for (final match in _bareHost.allMatches(lowered)) {
      final host = match.group(0)!;
      if (!_networkTlds.contains(host.split('.').last)) continue;
      if (!_isAllowedHost(host)) report(PrivacyFindingKind.host, host);
    }

    for (final match in _ipv4.allMatches(line)) {
      final address = match.group(0)!;
      if (!_isIpv4Literal(address)) continue;
      if (!_isAllowedIp(address)) {
        report(PrivacyFindingKind.ipAddress, address);
      }
    }

    for (final pattern in [_drivePath, _homePath]) {
      for (final match in pattern.allMatches(line)) {
        final path = match.group(0)!;
        if (allowedPaths.contains(path)) continue;
        report(PrivacyFindingKind.filesystemPath, path);
      }
    }
  }

  return findings;
}

/// What a scan of the working tree turned up.
final class RepositoryScan {
  const RepositoryScan({required this.scanned, required this.findings});

  /// How many text files were read.
  final int scanned;

  /// Findings by tracked path, in `git ls-files` order. Empty when clean.
  final Map<String, List<PrivacyFinding>> findings;

  /// Every finding rendered as `path:line: kind: value`.
  List<String> get report => [
    for (final entry in findings.entries)
      for (final finding in entry.value)
        '${entry.key}:${finding.line}: ${finding.kind.label}: ${finding.value}',
  ];
}

/// Scans every tracked file for private data.
///
/// Only tracked files are scanned, so a new file is covered from the moment it
/// is staged. Throws [ProcessException] when `git ls-files` cannot be run,
/// which is what happens outside a checkout.
Future<RepositoryScan> scanTrackedFiles() async {
  final listing = await Process.run(
    'git',
    ['ls-files'],
    runInShell: true,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (listing.exitCode != 0) {
    throw ProcessException('git', ['ls-files'], '${listing.stderr}'.trim());
  }

  final findings = <String, List<PrivacyFinding>>{};
  var scanned = 0;

  for (final path in (listing.stdout as String).split('\n')) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || exemptPaths.contains(trimmed)) continue;

    final file = File(trimmed);
    if (!file.existsSync()) continue;

    final bytes = file.readAsBytesSync();
    // Skip binaries the way git does: a NUL byte early in the file.
    if (bytes.take(8192).contains(0)) continue;

    final String contents;
    try {
      contents = utf8.decode(bytes);
    } on FormatException {
      continue;
    }

    scanned++;
    final found = findPrivateData(contents);
    if (found.isNotEmpty) findings[trimmed] = found;
  }

  return RepositoryScan(scanned: scanned, findings: findings);
}

Future<void> main() async {
  final RepositoryScan scan;
  try {
    scan = await scanTrackedFiles();
  } on ProcessException catch (error) {
    stderr.writeln('git ls-files failed: ${error.message}');
    exit(2);
  }

  if (scan.findings.isEmpty) {
    stdout.writeln('No private data in ${scan.scanned} tracked files.');
    return;
  }

  scan.report.forEach(stdout.writeln);
  stderr.writeln(
    '\n${scan.report.length} item(s) above must not be committed. If one of '
    'them is a genuinely public host or a synthetic path, add it to '
    'allowedHosts or allowedPaths in tool/check_privacy.dart.',
  );
  exit(1);
}

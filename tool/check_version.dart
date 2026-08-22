/// Verifies that a release tag agrees with the version in `pubspec.yaml`.
///
/// Usage: `dart run tool/check_version.dart v0.1.0`
///
/// Exits 0 when they agree, 1 with a message on stderr when they do not.
/// All the logic lives in [resolveVersion] so it can be unit tested without
/// touching the filesystem; `main` only does I/O.
library;

import 'dart:io';

/// Outcome of comparing a release tag against `pubspec.yaml`.
sealed class VersionCheck {
  const VersionCheck();
}

/// The tag and `pubspec.yaml` agree on [version] (no `v`, no `+build`).
final class VersionAgreed extends VersionCheck {
  final String version;
  const VersionAgreed(this.version);
}

/// The tag and `pubspec.yaml` do not agree; [message] explains why.
final class VersionRejected extends VersionCheck {
  final String message;
  const VersionRejected(this.message);
}

final RegExp _tagPattern = RegExp(r'^v(\d+\.\d+\.\d+)$');

// Anchored at column 0 so a nested `  version:` under some dependency cannot
// be mistaken for the package's own version.
final RegExp _versionLinePattern = RegExp(
  r'^version:[ \t]*(\S+)[ \t]*$',
  multiLine: true,
);

/// Compares [tagName] (e.g. `v0.1.0`) against the `version:` key in
/// [pubspecContents], ignoring any `+build` suffix on the pubspec side.
VersionCheck resolveVersion(String tagName, String pubspecContents) {
  final trimmedTag = tagName.trim();
  final tagMatch = _tagPattern.firstMatch(trimmedTag);
  if (tagMatch == null) {
    return VersionRejected(
      'Tag "$trimmedTag" is not of the form vX.Y.Z (for example v0.1.0).',
    );
  }
  final tagVersion = tagMatch.group(1)!;

  final versionMatch = _versionLinePattern.firstMatch(pubspecContents);
  if (versionMatch == null) {
    return const VersionRejected(
      'pubspec.yaml has no top-level "version:" key.',
    );
  }
  final pubspecVersion = versionMatch.group(1)!.split('+').first;

  if (pubspecVersion != tagVersion) {
    return VersionRejected(
      'Tag "$trimmedTag" declares version $tagVersion but pubspec.yaml '
      'declares $pubspecVersion. Update pubspec.yaml (or retag) so they match.',
    );
  }

  return VersionAgreed(tagVersion);
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/check_version.dart <tag>');
    exit(2);
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found - run this from the repo root.');
    exit(2);
  }

  final result = resolveVersion(args[0], pubspec.readAsStringSync());
  switch (result) {
    case VersionAgreed(:final version):
      stdout.writeln('Tag ${args[0]} matches pubspec.yaml version $version.');
      exit(0);
    case VersionRejected(:final message):
      stderr.writeln(message);
      exit(1);
  }
}

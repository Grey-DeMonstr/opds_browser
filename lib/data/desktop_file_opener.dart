import 'dart:io';

import 'package:opds_browser/domain/repositories.dart';

/// Runs the shell command that opens a file. Injected so tests never spawn a
/// process.
typedef RunProcess =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// A downloaded book could not be handed to the desktop shell.
class FileOpenException implements Exception {
  const FileOpenException(this.message);

  final String message;

  @override
  String toString() => 'FileOpenException: $message';
}

/// Opens a downloaded book with whatever the desktop has registered for it.
///
/// The Android build goes through an intent ([AndroidFileOpener]); the desktop
/// builds have no such channel, so they shell out instead.
class DesktopFileOpener implements FileOpener {
  DesktopFileOpener({String? operatingSystem, RunProcess? runProcess})
    : _os = operatingSystem ?? Platform.operatingSystem,
      _run = runProcess ?? Process.run;

  final String _os;
  final RunProcess _run;

  @override
  Future<void> open(String uri, String mimeType) async {
    // `start` is a cmd built-in, and its first quoted argument is the window
    // title — hence the empty string before the path.
    final (executable, arguments) = switch (_os) {
      'windows' => ('cmd', ['/c', 'start', '', uri]),
      'macos' => ('open', [uri]),
      'linux' => ('xdg-open', [uri]),
      _ => throw FileOpenException('Cannot open files on $_os.'),
    };

    final ProcessResult result;
    try {
      result = await _run(executable, arguments);
    } on ProcessException catch (e) {
      throw FileOpenException(e.message);
    }
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw FileOpenException(
        stderr.isEmpty ? 'The shell refused to open the file.' : stderr,
      );
    }
  }
}

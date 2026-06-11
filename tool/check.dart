import 'dart:io';

/// Runs `flutter <args>`, streaming output to this process's stdio.
/// Returns the child's exit code.
Future<int> _runFlutter(String label, List<String> args) async {
  stdout.writeln('\n=== $label: flutter ${args.join(' ')} ===');
  final process = await Process.start(
    'flutter',
    args,
    runInShell: true, // resolves flutter.bat on Windows
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

Future<void> main() async {
  final analyzeCode = await _runFlutter('analyze', ['analyze']);
  if (analyzeCode != 0) {
    stderr.writeln('\nflutter analyze failed.');
    exit(analyzeCode);
  }

  final testCode = await _runFlutter('test', ['test']);
  if (testCode != 0) {
    stderr.writeln('\nflutter test failed.');
    exit(testCode);
  }

  stdout.writeln('\nAll checks passed.');
}

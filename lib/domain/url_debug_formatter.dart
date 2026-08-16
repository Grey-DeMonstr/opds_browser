/// Renders [url] for the in-app debug panel: host-less, fully decoded, one
/// query parameter per line.
///
/// The first line is the decoded path; each following line is a single
/// `key=value` pair with percent-escapes (and `+`) resolved, so non-ASCII
/// values such as Cyrillic titles read as plain text. A fragment, if any,
/// is appended as a final `#fragment` line.
String formatUrlForDebug(Uri url) {
  final lines = <String>[url.path.isEmpty ? '/' : _decode(url.path)];
  url.queryParametersAll.forEach((key, values) {
    for (final value in values) {
      lines.add('$key=$value');
    }
  });
  if (url.fragment.isNotEmpty) lines.add('#${url.fragment}');
  return lines.join('\n');
}

/// Percent-decodes [s], leaving it untouched if it holds a malformed escape.
String _decode(String s) {
  try {
    return Uri.decodeFull(s);
  } on ArgumentError {
    return s;
  } on FormatException {
    return s;
  }
}

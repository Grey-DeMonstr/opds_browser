/// Renders [url] for a catalogue row: the scheme dropped and no trailing
/// slash, so `https://opds.example.org/opds/` reads as `opds.example.org/opds`.
///
/// Everything after the authority is kept, query string included — the row
/// shows a shortened URL, not a different one.
String formatCatalogUrl(Uri url) {
  final text = url.toString();
  final prefix = '${url.scheme}://';
  var out = text.startsWith(prefix) ? text.substring(prefix.length) : text;
  if (out.endsWith('/')) out = out.substring(0, out.length - 1);
  return out;
}

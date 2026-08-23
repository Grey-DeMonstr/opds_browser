import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/url_debug_formatter.dart';

void main() {
  group('formatUrlForDebug', () {
    test('hides scheme, host and port', () {
      final url = Uri.parse('https://example.com:8080/authors');
      expect(formatUrlForDebug(url), '/authors');
    });

    test('puts each query parameter on its own line without &', () {
      final url = Uri.parse(
        'https://example.com/authors?author=John%20Smith&series=Some%20Book%20Series',
      );
      expect(
        formatUrlForDebug(url),
        '/authors\nauthor=John Smith\nseries=Some Book Series',
      );
    });

    test('decodes percent-encoded non-ASCII values', () {
      final url = Uri.parse(
        'https://example.com/opds/series/La%20Com%C3%A9die%20humaine'
        '?q=P%C3%A8re%20Goriot',
      );
      expect(
        formatUrlForDebug(url),
        '/opds/series/La Comédie humaine\nq=Père Goriot',
      );
    });

    test('decodes + as space in query values', () {
      final url = Uri.parse('https://example.com/s?author=John+Smith');
      expect(formatUrlForDebug(url), '/s\nauthor=John Smith');
    });

    test('repeats a key that occurs more than once', () {
      final url = Uri.parse('https://example.com/s?tag=a&tag=b');
      expect(formatUrlForDebug(url), '/s\ntag=a\ntag=b');
    });

    test('keeps a parameter with an empty value', () {
      final url = Uri.parse('https://example.com/s?author=&x=1');
      expect(formatUrlForDebug(url), '/s\nauthor=\nx=1');
    });

    test('falls back to / for an empty path', () {
      expect(formatUrlForDebug(Uri.parse('https://example.com')), '/');
      expect(formatUrlForDebug(Uri.parse('https://example.com?a=1')), '/\na=1');
    });

    test('leaves a malformed percent escape as-is', () {
      final url = Uri.parse('https://example.com/a%ZZb');
      expect(formatUrlForDebug(url), '/a%ZZb');
    });

    test('appends the fragment when present', () {
      final url = Uri.parse('https://example.com/p?a=1#frag');
      expect(formatUrlForDebug(url), '/p\na=1\n#frag');
    });
  });
}

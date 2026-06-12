import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/url_normalizer.dart';

void main() {
  group('normalizeUrl', () {
    test('strips fragment', () {
      expect(normalizeUrl(Uri.parse('http://a.com/p#frag')), 'http://a.com/p');
    });

    test('removes default HTTP port 80', () {
      expect(normalizeUrl(Uri.parse('http://a.com:80/p')), 'http://a.com/p');
    });

    test('removes default HTTPS port 443', () {
      expect(normalizeUrl(Uri.parse('https://a.com:443/p')), 'https://a.com/p');
    });

    test('keeps non-default port', () {
      expect(normalizeUrl(Uri.parse('http://a.com:8080/p')), 'http://a.com:8080/p');
    });

    test('lowercases scheme and host (via Uri.parse)', () {
      expect(normalizeUrl(Uri.parse('http://A.COM/p')), 'http://a.com/p');
    });

    test('preserves query string', () {
      expect(normalizeUrl(Uri.parse('http://a.com/p?q=1')), 'http://a.com/p?q=1');
    });

    test('strips fragment and default port together', () {
      expect(
        normalizeUrl(Uri.parse('https://a.com:443/p?q=1#frag')),
        'https://a.com/p?q=1',
      );
    });
  });
}

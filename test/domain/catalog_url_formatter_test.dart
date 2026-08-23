import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/catalog_url_formatter.dart';

void main() {
  test('drops the scheme', () {
    expect(
      formatCatalogUrl(Uri.parse('https://opds.example.org/opds')),
      'opds.example.org/opds',
    );
  });

  test('drops a trailing slash', () {
    expect(
      formatCatalogUrl(Uri.parse('https://gutenberg.org/opds/')),
      'gutenberg.org/opds',
    );
  });

  test('keeps a bare host as-is', () {
    expect(formatCatalogUrl(Uri.parse('http://example.com')), 'example.com');
  });

  test('keeps the query string', () {
    expect(
      formatCatalogUrl(Uri.parse('https://example.com/opds?id=root')),
      'example.com/opds?id=root',
    );
  });

  test('keeps a non-default port', () {
    expect(
      formatCatalogUrl(Uri.parse('http://192.0.2.10:8080/opds')),
      '192.0.2.10:8080/opds',
    );
  });
}

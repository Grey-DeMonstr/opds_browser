import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/default_catalogs.dart';

void main() {
  group('defaultCatalogs', () {
    test('includes Project Gutenberg', () {
      final gutenberg = defaultCatalogs.singleWhere(
        (c) => c.title == 'Project Gutenberg',
      );
      expect(gutenberg.rootUrl, 'https://www.gutenberg.org/ebooks.opds/');
    });

    test('every entry has a non-empty title and an absolute https URL', () {
      expect(defaultCatalogs, isNotEmpty);
      for (final catalog in defaultCatalogs) {
        expect(catalog.title, isNotEmpty);
        final url = Uri.parse(catalog.rootUrl);
        expect(url.isAbsolute, isTrue, reason: catalog.rootUrl);
        expect(url.scheme, 'https', reason: catalog.rootUrl);
      }
    });

    test('titles are unique', () {
      final titles = defaultCatalogs.map((c) => c.title).toSet();
      expect(titles, hasLength(defaultCatalogs.length));
    });
  });
}

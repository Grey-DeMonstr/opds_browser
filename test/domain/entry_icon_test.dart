import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entry_icon.dart';

void main() {
  EntryGlyph glyph(String url) => glyphForEntryUrl(Uri.parse(url));

  group('glyphForEntryUrl', () {
    test('reads the section from the path, whatever the title says', () {
      // The reference catalogue publishes Russian titles on English paths.
      expect(glyph('https://example.com/opds/author'), EntryGlyph.author);
      expect(glyph('https://example.com/opds/series'), EntryGlyph.series);
      expect(glyph('https://example.com/opds/title'), EntryGlyph.title);
      expect(glyph('https://example.com/opds/genre'), EntryGlyph.genre);
    });

    test('plurals and longer names still match', () {
      expect(glyph('https://example.com/opds/authors'), EntryGlyph.author);
      expect(glyph('https://example.com/opds/genres/all'), EntryGlyph.genre);
      expect(glyph('https://example.com/opds/titles?x=1'), EntryGlyph.title);
    });

    test('an unrecognised section gets the neutral folder glyph', () {
      expect(glyph('https://example.com/opds/latest'), EntryGlyph.folder);
      expect(glyph('https://example.com/opds'), EntryGlyph.folder);
    });

    test('a shared parent segment does not colour every section', () {
      // Project Gutenberg hangs its whole root under /ebooks/. Matching a
      // keyword anywhere in the URL would call all of it "titles".
      expect(glyph('https://example.com/ebooks/'), EntryGlyph.folder);
      expect(glyph('https://example.com/ebooks/latest/'), EntryGlyph.folder);
      expect(glyph('https://example.com/ebooks/author/123'), EntryGlyph.author);
    });

    test('a section expressed as a query is read too', () {
      expect(
        glyph('https://example.com/opds/browse?by=author'),
        EntryGlyph.author,
      );
    });

    test('a query that merely contains a keyword is not a match', () {
      // Only a whole value counts; a search term must not pick a glyph.
      expect(
        glyph('https://example.com/opds/find?q=authorship+studies'),
        EntryGlyph.folder,
      );
    });

    test('matching ignores case', () {
      expect(glyph('https://example.com/OPDS/Author'), EntryGlyph.author);
    });
  });
}

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
      expect(glyph('https://example.com/opds/misc'), EntryGlyph.folder);
      expect(glyph('https://example.com/opds'), EntryGlyph.folder);
    });

    test('a shared parent segment does not colour every section', () {
      // Project Gutenberg hangs its whole root under /ebooks/. Matching a
      // keyword anywhere in the URL would call all of it "titles".
      expect(glyph('https://example.com/ebooks/'), EntryGlyph.folder);
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

    test('a sort order names the section when the path does not', () {
      // Project Gutenberg hangs its whole root off one path and distinguishes
      // the sections by query alone.
      expect(
        glyph('https://example.com/ebooks/search.opds/?sort_order=downloads'),
        EntryGlyph.popular,
      );
      expect(
        glyph(
          'https://example.com/ebooks/search.opds/?sort_order=release_date',
        ),
        EntryGlyph.newest,
      );
      expect(
        glyph('https://example.com/ebooks/search.opds/?sort_order=random'),
        EntryGlyph.random,
      );
    });

    test('the same sections named in a path are read too', () {
      expect(glyph('https://example.com/opds/popular'), EntryGlyph.popular);
      expect(glyph('https://example.com/opds/latest'), EntryGlyph.newest);
      expect(glyph('https://example.com/opds/random'), EntryGlyph.random);
    });

    test('a longer word is not cut down to one of these', () {
      // "newspapers" is a folder of newspapers, not the newest anything.
      expect(glyph('https://example.com/opds/newspapers'), EntryGlyph.folder);
    });

    test('matching ignores case', () {
      expect(glyph('https://example.com/OPDS/Author'), EntryGlyph.author);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/browse_list.dart';
import 'package:opds_browser/domain/models.dart';

NavigationEntry _nav(String title, [String? subtitle]) => NavigationEntry(
  title: title,
  subtitle: subtitle,
  url: Uri.parse('https://example.org/${Uri.encodeComponent(title)}'),
);

BookEntry _book(String title) =>
    BookEntry(title: title, authors: const [], acquisitionLinks: const []);

void main() {
  group('splitEntryCount', () {
    test('splits a leading count from its unit', () {
      expect(splitEntryCount('930 authors'), (count: '930', unit: 'authors'));
    });

    test('keeps a multi-word unit whole', () {
      expect(splitEntryCount('1 book by this author'), (
        count: '1',
        unit: 'book by this author',
      ));
    });

    test(
      'leaves the count empty when the text does not start with a number',
      () {
        expect(splitEntryCount('Books by this author'), (
          count: '',
          unit: 'Books by this author',
        ));
      },
    );

    test('reads a count with no unit after it', () {
      expect(splitEntryCount('42'), (count: '42', unit: ''));
    });

    test('is empty for a missing subtitle', () {
      expect(splitEntryCount(null), (count: '', unit: ''));
    });
  });

  group('isPrefixBucket', () {
    test('recognises a synthesised alphabetic bucket', () {
      expect(isPrefixBucket('DIC~'), isTrue);
    });

    test('a real entry is not a bucket', () {
      expect(isPrefixBucket('Dickens, Charles'), isFalse);
    });

    test('an empty title is not a bucket', () {
      expect(isPrefixBucket(''), isFalse);
    });
  });

  group('filterBrowseEntries', () {
    final entries = <FeedEntry>[
      _nav('DIC~', '5 authors'),
      _nav('Dickens, Charles', '214 books'),
      _book('Great Expectations'),
    ];

    test('returns everything by default', () {
      expect(
        filterBrowseEntries(entries, bucketsHidden: false, query: ''),
        hasLength(3),
      );
    });

    test('hiding buckets drops the synthesised folders only', () {
      final filtered = filterBrowseEntries(
        entries,
        bucketsHidden: true,
        query: '',
      );

      expect(filtered.map(browseEntryTitle), [
        'Dickens, Charles',
        'Great Expectations',
      ]);
    });

    test('a query matches titles regardless of case', () {
      final filtered = filterBrowseEntries(
        entries,
        bucketsHidden: false,
        query: 'dickens',
      );

      expect(filtered.map(browseEntryTitle), ['Dickens, Charles']);
    });

    test('a query also matches book entries', () {
      final filtered = filterBrowseEntries(
        entries,
        bucketsHidden: false,
        query: 'expectations',
      );

      expect(filtered.map(browseEntryTitle), ['Great Expectations']);
    });

    test('a query and hidden buckets apply together', () {
      final filtered = filterBrowseEntries(
        entries,
        bucketsHidden: true,
        query: 'dic',
      );

      expect(filtered.map(browseEntryTitle), ['Dickens, Charles']);
    });
  });

  group('isSingleBookCandidate', () {
    test('an acquisition-kind folder is worth resolving', () {
      final entry = NavigationEntry(
        title: 'The Terrible Stranger (fb2)',
        url: Uri.parse('https://example.com/opds/book?uid=one'),
        linkType: 'application/atom+xml;profile=opds-catalog;kind=acquisition',
      );

      expect(isSingleBookCandidate(entry), isTrue);
    });

    test('a navigation-kind folder is left alone, whatever it claims', () {
      final entry = NavigationEntry(
        title: 'Series: Anthology',
        subtitle: '1 book by this author',
        url: Uri.parse('https://example.com/opds/author?series=Anthology'),
        linkType: 'application/atom+xml;profile=opds-catalog;kind=navigation',
      );

      expect(isSingleBookCandidate(entry), isFalse);
    });

    test('spacing and case in the declared type do not matter', () {
      final entry = NavigationEntry(
        title: 'One Book',
        url: Uri.parse('https://example.com/opds/book?uid=one'),
        linkType:
            'Application/Atom+XML; profile=opds-catalog; kind=acquisition',
      );

      expect(isSingleBookCandidate(entry), isTrue);
    });

    test('a folder from a cache written before link types is left alone', () {
      final entry = NavigationEntry(
        title: 'Science Fiction',
        url: Uri.parse('https://example.com/opds/sci-fi'),
      );

      expect(isSingleBookCandidate(entry), isFalse);
    });
  });

  group('soleBookOf', () {
    BookEntry downloadable(String title) => BookEntry(
      title: title,
      authors: const ['Olga Gromyko'],
      acquisitionLinks: [
        AcquisitionLink(
          url: Uri.parse('https://example.com/book/$title'),
          mimeType: 'application/fb2',
          formatLabel: 'FB2',
        ),
      ],
    );

    test('returns the one book a wrapper feed holds', () {
      final book = downloadable('Stringy');
      final feed = ParsedFeed(title: 'Book', entries: [book]);

      expect(soleBookOf(feed), same(book));
    });

    test('returns null when the feed holds two books', () {
      final feed = ParsedFeed(
        title: 'Series',
        entries: [downloadable('One'), downloadable('Two')],
      );

      expect(soleBookOf(feed), isNull);
    });

    test('returns null when the feed is empty', () {
      expect(soleBookOf(const ParsedFeed(title: 'Empty', entries: [])), isNull);
    });

    test('returns null when the one entry is another folder', () {
      final feed = ParsedFeed(title: 'Nested', entries: [_nav('Deeper')]);

      expect(soleBookOf(feed), isNull);
    });

    test('returns null when the one book has nothing to download', () {
      final feed = ParsedFeed(title: 'Book', entries: [_book('Unavailable')]);

      expect(soleBookOf(feed), isNull);
    });
  });
}

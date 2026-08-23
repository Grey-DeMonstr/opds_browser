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
}

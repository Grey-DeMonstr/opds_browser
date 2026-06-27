import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/models.dart';

void main() {
  group('AcquisitionLink', () {
    test('toJson / fromJson roundtrip', () {
      final link = AcquisitionLink(
        url: Uri.parse('https://example.com/book.fb2'),
        mimeType: 'application/fb2',
        formatLabel: 'FB2',
      );
      final json = link.toJson();
      expect(json['url'], 'https://example.com/book.fb2');
      expect(json['mimeType'], 'application/fb2');
      expect(json['formatLabel'], 'FB2');
      final restored = AcquisitionLink.fromJson(json);
      expect(restored.url, link.url);
      expect(restored.mimeType, link.mimeType);
      expect(restored.formatLabel, link.formatLabel);
    });
  });

  group('NavigationEntry', () {
    test('toJson / fromJson roundtrip — with subtitle', () {
      final entry = NavigationEntry(
        title: 'Science Fiction',
        subtitle: 'Explore the cosmos',
        url: Uri.parse('https://example.com/sci-fi'),
      );
      final json = entry.toJson();
      expect(json['type'], 'nav');
      expect(json['title'], 'Science Fiction');
      expect(json['subtitle'], 'Explore the cosmos');
      expect(json['url'], 'https://example.com/sci-fi');
      final restored = NavigationEntry.fromJson(json);
      expect(restored.title, entry.title);
      expect(restored.subtitle, entry.subtitle);
      expect(restored.url, entry.url);
    });

    test('toJson omits subtitle when null; fromJson restores null', () {
      final entry = NavigationEntry(
        title: 'Fantasy',
        subtitle: null,
        url: Uri.parse('https://example.com/fantasy'),
      );
      final json = entry.toJson();
      expect(json.containsKey('subtitle'), isFalse);
      final restored = NavigationEntry.fromJson(json);
      expect(restored.subtitle, isNull);
    });
  });

  group('BookEntry', () {
    test('toJson / fromJson roundtrip — all fields present', () {
      final entry = BookEntry(
        title: 'The Dart Language',
        authors: ['Alice Author', 'Bob Coauthor'],
        series: 'Dart Series',
        seriesIndex: 1.5,
        summary: 'An intro to Dart.',
        coverUrl: Uri.parse('https://example.com/cover.jpg'),
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/book.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      );
      final json = entry.toJson();
      expect(json['type'], 'book');
      expect(json['title'], 'The Dart Language');
      expect(json['authors'], ['Alice Author', 'Bob Coauthor']);
      expect(json['series'], 'Dart Series');
      expect(json['seriesIndex'], 1.5);
      expect(json['summary'], 'An intro to Dart.');
      expect(json['coverUrl'], 'https://example.com/cover.jpg');
      expect((json['acquisitionLinks'] as List<dynamic>).length, 1);

      final restored = BookEntry.fromJson(json);
      expect(restored.title, entry.title);
      expect(restored.authors, entry.authors);
      expect(restored.series, entry.series);
      expect(restored.seriesIndex, entry.seriesIndex);
      expect(restored.summary, entry.summary);
      expect(restored.coverUrl, entry.coverUrl);
      expect(restored.acquisitionLinks.length, 1);
      expect(restored.acquisitionLinks.first.formatLabel, 'FB2');
    });

    test('toJson omits nullable fields when null; fromJson restores nulls', () {
      final entry = BookEntry(
        title: 'Minimal Book',
        authors: const [],
        series: null,
        seriesIndex: null,
        summary: null,
        coverUrl: null,
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/min.epub'),
            mimeType: 'application/epub+zip',
            formatLabel: 'EPUB',
          ),
        ],
      );
      final json = entry.toJson();
      expect(json.containsKey('series'), isFalse);
      expect(json.containsKey('seriesIndex'), isFalse);
      expect(json.containsKey('summary'), isFalse);
      expect(json.containsKey('coverUrl'), isFalse);
      expect(json['authors'], isEmpty);

      final restored = BookEntry.fromJson(json);
      expect(restored.series, isNull);
      expect(restored.seriesIndex, isNull);
      expect(restored.summary, isNull);
      expect(restored.coverUrl, isNull);
      expect(restored.authors, isEmpty);
    });

    test('integer seriesIndex round-trips as double', () {
      final entry = BookEntry(
        title: 'Book 1',
        authors: const ['Author'],
        series: 'Series',
        seriesIndex: 1.0,
        summary: null,
        coverUrl: null,
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/b.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      );
      final restored = BookEntry.fromJson(entry.toJson());
      expect(restored.seriesIndex, 1.0);
    });
  });

  group('FeedEntry.fromJson', () {
    test('dispatches to NavigationEntry for type "nav"', () {
      final nav = NavigationEntry(
        title: 'Test Nav',
        subtitle: null,
        url: Uri.parse('https://example.com/nav'),
      );
      final restored = FeedEntry.fromJson(nav.toJson());
      expect(restored, isA<NavigationEntry>());
      expect((restored as NavigationEntry).title, 'Test Nav');
    });

    test('dispatches to BookEntry for type "book"', () {
      final book = BookEntry(
        title: 'Test Book',
        authors: const ['Author'],
        series: null,
        seriesIndex: null,
        summary: null,
        coverUrl: null,
        acquisitionLinks: [
          AcquisitionLink(
            url: Uri.parse('https://example.com/book.fb2'),
            mimeType: 'application/fb2',
            formatLabel: 'FB2',
          ),
        ],
      );
      final restored = FeedEntry.fromJson(book.toJson());
      expect(restored, isA<BookEntry>());
    });

    test('throws FormatException for unknown type', () {
      expect(
        () => FeedEntry.fromJson({'type': 'unknown'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ParsedFeed', () {
    test('toJson / fromJson roundtrip — mixed entries and pagination', () {
      final feed = ParsedFeed(
        title: 'Test Feed',
        entries: [
          NavigationEntry(
            title: 'Nav Entry',
            subtitle: null,
            url: Uri.parse('https://example.com/nav'),
          ),
          BookEntry(
            title: 'Book Entry',
            authors: const ['Auth'],
            series: null,
            seriesIndex: null,
            summary: null,
            coverUrl: null,
            acquisitionLinks: [
              AcquisitionLink(
                url: Uri.parse('https://example.com/book.fb2'),
                mimeType: 'application/fb2',
                formatLabel: 'FB2',
              ),
            ],
          ),
        ],
        nextPageUrl: Uri.parse('https://example.com/feed?page=2'),
      );
      final restored = ParsedFeed.fromJson(feed.toJson());
      expect(restored.title, 'Test Feed');
      expect(restored.entries.length, 2);
      expect(restored.entries[0], isA<NavigationEntry>());
      expect(restored.entries[1], isA<BookEntry>());
      expect(
        restored.nextPageUrl,
        Uri.parse('https://example.com/feed?page=2'),
      );
    });

    test('toJson omits nextPageUrl when null; fromJson restores null', () {
      final feed = ParsedFeed(
        title: 'Last Page',
        entries: const [],
        nextPageUrl: null,
      );
      final json = feed.toJson();
      expect(json.containsKey('nextPageUrl'), isFalse);
      expect(json['entries'], isEmpty);
      final restored = ParsedFeed.fromJson(json);
      expect(restored.nextPageUrl, isNull);
      expect(restored.entries, isEmpty);
    });
  });
}

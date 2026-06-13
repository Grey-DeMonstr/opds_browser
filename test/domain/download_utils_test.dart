import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

AcquisitionLink _link(String label) => AcquisitionLink(
      url: Uri.parse('https://example.com/${label.toLowerCase()}'),
      mimeType: 'application/octet-stream',
      formatLabel: label,
    );

BookEntry _book({
  String title = 'Book Title',
  List<String> authors = const ['Jane Doe'],
  String? series,
  double? seriesIndex,
  List<AcquisitionLink>? links,
}) =>
    BookEntry(
      title: title,
      authors: authors,
      series: series,
      seriesIndex: seriesIndex,
      acquisitionLinks: links ?? [_link('FB2')],
    );

void main() {
  // ── preferredLink ──────────────────────────────────────────────────────────

  group('preferredLink', () {
    test('empty list returns null', () {
      expect(preferredLink([]), isNull);
    });

    test('single link is returned directly', () {
      final link = _link('EPUB');
      expect(preferredLink([link]), same(link));
    });

    test('FB2.ZIP preferred over FB2 when both present', () {
      final fb2 = _link('FB2');
      final zip = _link('FB2.ZIP');
      final epub = _link('EPUB');
      expect(preferredLink([fb2, epub, zip]), same(zip));
    });

    test('FB2 returned when only FB2 present among multiple', () {
      final fb2 = _link('FB2');
      final epub = _link('EPUB');
      expect(preferredLink([epub, fb2]), same(fb2));
    });

    test('returns null when multiple links but no FB2 variant', () {
      expect(preferredLink([_link('EPUB'), _link('PDF')]), isNull);
    });
  });

  // ── buildFileName ──────────────────────────────────────────────────────────

  group('buildFileName', () {
    test('single author, series with integer index', () {
      final book = _book(series: 'Great Series', seriesIndex: 1.0);
      expect(
        buildFileName(book, _link('FB2')),
        'Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('two authors joined with comma', () {
      final book = _book(authors: ['Jane Doe', 'John Smith']);
      expect(
        buildFileName(book, _link('EPUB')),
        'Jane Doe, John Smith - Book Title.epub',
      );
    });

    test('three or more authors appends et al.', () {
      final book = _book(authors: ['A', 'B', 'C']);
      expect(buildFileName(book, _link('PDF')), 'A et al. - Book Title.pdf');
    });

    test('no authors — author segment omitted entirely', () {
      final book = _book(authors: []);
      expect(buildFileName(book, _link('FB2')), 'Book Title.fb2');
    });

    test('no series — series segment omitted', () {
      expect(buildFileName(_book(), _link('FB2')), 'Jane Doe - Book Title.fb2');
    });

    test('series with no index — no #index', () {
      final book = _book(series: 'My Series');
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - My Series - Book Title.fb2');
    });

    test('seriesIndex 1.0 formats as "1"', () {
      final book = _book(series: 'S', seriesIndex: 1.0);
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - S #1 - Book Title.fb2');
    });

    test('seriesIndex 1.5 formats as "1.5"', () {
      final book = _book(series: 'S', seriesIndex: 1.5);
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - S #1.5 - Book Title.fb2');
    });

    test('FB2.ZIP extension is fb2.zip', () {
      expect(buildFileName(_book(), _link('FB2.ZIP')), 'Jane Doe - Book Title.fb2.zip');
    });

    test('EPUB extension is epub', () {
      expect(buildFileName(_book(), _link('EPUB')), 'Jane Doe - Book Title.epub');
    });

    test('illegal chars in title replaced with _', () {
      final book = _book(title: 'Title: A/B*C');
      expect(buildFileName(book, _link('FB2')), 'Jane Doe - Title_ A_B_C.fb2');
    });

    test('filename capped at 200 chars, extension preserved', () {
      final book = _book(title: 'T' * 300);
      final result = buildFileName(book, _link('FB2'));
      expect(result.length, lessThanOrEqualTo(200));
      expect(result.endsWith('.fb2'), isTrue);
    });
  });

  // ── buildPathSegments ──────────────────────────────────────────────────────

  group('buildPathSegments', () {
    const system = AppSettings(target: SystemDownloads());

    test('both flags off — empty list', () {
      expect(buildPathSegments(system, _book(series: 'S')), isEmpty);
    });

    test('author flag on — author segment added', () {
      const s = AppSettings(target: SystemDownloads(), createAuthorFolder: true);
      expect(buildPathSegments(s, _book()), ['Jane Doe']);
    });

    test('series flag on — series segment added', () {
      const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
      expect(buildPathSegments(s, _book(series: 'Great Series')), ['Great Series']);
    });

    test('both flags on — author then series', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(
        buildPathSegments(s, _book(series: 'Great Series')),
        ['Jane Doe', 'Great Series'],
      );
    });

    test('author flag on but authors empty — no folder created', () {
      const s = AppSettings(target: SystemDownloads(), createAuthorFolder: true);
      expect(buildPathSegments(s, _book(authors: [])), isEmpty);
    });

    test('series flag on but series null — no folder created', () {
      const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
      expect(buildPathSegments(s, _book()), isEmpty);
    });
  });
}

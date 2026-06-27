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
}) => BookEntry(
  title: title,
  authors: authors,
  series: series,
  seriesIndex: seriesIndex,
  acquisitionLinks: links ?? [_link('FB2')],
);

const _noFolders = AppSettings(target: SystemDownloads());
const _authorFolder = AppSettings(
  target: SystemDownloads(),
  createAuthorFolder: true,
);
const _seriesFolder = AppSettings(
  target: SystemDownloads(),
  createSeriesFolder: true,
);
const _bothFolders = AppSettings(
  target: SystemDownloads(),
  createAuthorFolder: true,
  createSeriesFolder: true,
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
        buildFileName(book, _link('FB2'), _noFolders),
        'Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('two authors joined with comma', () {
      final book = _book(authors: ['Jane Doe', 'John Smith']);
      expect(
        buildFileName(book, _link('EPUB'), _noFolders),
        'Jane Doe, John Smith - Book Title.epub',
      );
    });

    test('three or more authors appends et al.', () {
      final book = _book(authors: ['A', 'B', 'C']);
      expect(
        buildFileName(book, _link('PDF'), _noFolders),
        'A et al. - Book Title.pdf',
      );
    });

    test('no authors — author segment omitted entirely', () {
      final book = _book(authors: []);
      expect(buildFileName(book, _link('FB2'), _noFolders), 'Book Title.fb2');
    });

    test('no series — series segment omitted', () {
      expect(
        buildFileName(_book(), _link('FB2'), _noFolders),
        'Jane Doe - Book Title.fb2',
      );
    });

    test('series with no index — no #index', () {
      final book = _book(series: 'My Series');
      expect(
        buildFileName(book, _link('FB2'), _noFolders),
        'Jane Doe - My Series - Book Title.fb2',
      );
    });

    test('seriesIndex 1.0 formats as "1"', () {
      final book = _book(series: 'S', seriesIndex: 1.0);
      expect(
        buildFileName(book, _link('FB2'), _noFolders),
        'Jane Doe - S #1 - Book Title.fb2',
      );
    });

    test('seriesIndex 1.5 formats as "1.5"', () {
      final book = _book(series: 'S', seriesIndex: 1.5);
      expect(
        buildFileName(book, _link('FB2'), _noFolders),
        'Jane Doe - S #1.5 - Book Title.fb2',
      );
    });

    test('FB2.ZIP extension is fb2.zip', () {
      expect(
        buildFileName(_book(), _link('FB2.ZIP'), _noFolders),
        'Jane Doe - Book Title.fb2.zip',
      );
    });

    test('EPUB extension is epub', () {
      expect(
        buildFileName(_book(), _link('EPUB'), _noFolders),
        'Jane Doe - Book Title.epub',
      );
    });

    test('illegal chars in title replaced with _', () {
      final book = _book(title: 'Title: A/B*C');
      expect(
        buildFileName(book, _link('FB2'), _noFolders),
        'Jane Doe - Title_ A_B_C.fb2',
      );
    });

    test('filename capped at 200 chars, extension preserved', () {
      final book = _book(title: 'T' * 300);
      final result = buildFileName(book, _link('FB2'), _noFolders);
      expect(result.length, lessThanOrEqualTo(200));
      expect(result.endsWith('.fb2'), isTrue);
    });

    test('author folder enabled — author omitted from filename', () {
      final book = _book(series: 'Great Series', seriesIndex: 1.0);
      expect(
        buildFileName(book, _link('FB2'), _authorFolder),
        'Great Series #1 - Book Title.fb2',
      );
    });

    test('series folder enabled — series omitted from filename', () {
      final book = _book(series: 'Great Series', seriesIndex: 1.0);
      expect(
        buildFileName(book, _link('FB2'), _seriesFolder),
        'Jane Doe - Book Title.fb2',
      );
    });

    test('both folders enabled — author and series omitted from filename', () {
      final book = _book(series: 'Great Series', seriesIndex: 1.0);
      expect(buildFileName(book, _link('FB2'), _bothFolders), 'Book Title.fb2');
    });

    test('author folder enabled but no authors — title only', () {
      final book = _book(authors: [], series: 'S', seriesIndex: 1.0);
      expect(
        buildFileName(book, _link('FB2'), _authorFolder),
        'S #1 - Book Title.fb2',
      );
    });

    test('series folder enabled but no series — author still included', () {
      expect(
        buildFileName(_book(), _link('FB2'), _seriesFolder),
        'Jane Doe - Book Title.fb2',
      );
    });

    test(
      'entry.series null, inferredSeries provided, series folder off — inferred series in filename',
      () {
        expect(
          buildFileName(
            _book(),
            _link('FB2'),
            _noFolders,
            inferredSeries: 'Inferred Series',
          ),
          'Jane Doe - Inferred Series - Book Title.fb2',
        );
      },
    );

    test(
      'entry.series null, inferredSeries provided, series folder on — series omitted from filename',
      () {
        expect(
          buildFileName(
            _book(),
            _link('FB2'),
            _seriesFolder,
            inferredSeries: 'Inferred Series',
          ),
          'Jane Doe - Book Title.fb2',
        );
      },
    );

    test(
      'entry.series set — real series used in filename, inferredSeries ignored',
      () {
        final book = _book(series: 'Real Series');
        expect(
          buildFileName(
            book,
            _link('FB2'),
            _noFolders,
            inferredSeries: 'Inferred Series',
          ),
          'Jane Doe - Real Series - Book Title.fb2',
        );
      },
    );
  });

  // ── buildPathSegments ──────────────────────────────────────────────────────

  group('buildPathSegments', () {
    const system = AppSettings(target: SystemDownloads());

    test('both flags off — empty list', () {
      expect(buildPathSegments(system, _book(series: 'S')), isEmpty);
    });

    test('author flag on — author segment added', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
      );
      expect(buildPathSegments(s, _book()), ['Jane Doe']);
    });

    test('series flag on — series segment added', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createSeriesFolder: true,
      );
      expect(buildPathSegments(s, _book(series: 'Great Series')), [
        'Great Series',
      ]);
    });

    test('both flags on — author then series', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(buildPathSegments(s, _book(series: 'Great Series')), [
        'Jane Doe',
        'Great Series',
      ]);
    });

    test('author flag on but authors empty — no folder created', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
      );
      expect(buildPathSegments(s, _book(authors: [])), isEmpty);
    });

    test('series flag on but series null — no folder created', () {
      const s = AppSettings(
        target: SystemDownloads(),
        createSeriesFolder: true,
      );
      expect(buildPathSegments(s, _book()), isEmpty);
    });

    test(
      'series flag on, entry.series null, inferredSeries provided — inferred series folder created',
      () {
        const s = AppSettings(
          target: SystemDownloads(),
          createSeriesFolder: true,
        );
        expect(
          buildPathSegments(s, _book(), inferredSeries: 'Inferred Series'),
          ['Inferred Series'],
        );
      },
    );

    test(
      'series flag on — real entry.series takes precedence over inferredSeries',
      () {
        const s = AppSettings(
          target: SystemDownloads(),
          createSeriesFolder: true,
        );
        expect(
          buildPathSegments(
            s,
            _book(series: 'Real Series'),
            inferredSeries: 'Inferred Series',
          ),
          ['Real Series'],
        );
      },
    );

    test(
      'series flag on, entry.series null, inferredSeries null — no folder',
      () {
        const s = AppSettings(
          target: SystemDownloads(),
          createSeriesFolder: true,
        );
        expect(buildPathSegments(s, _book(), inferredSeries: null), isEmpty);
      },
    );
  });

  // ── folderPreferredLink ───────────────────────────────────────────────────

  group('folderPreferredLink', () {
    test('single link returned directly', () {
      final link = _link('EPUB');
      expect(folderPreferredLink([link]), same(link));
    });

    test('FB2.ZIP preferred over EPUB when present', () {
      final fb2zip = _link('FB2.ZIP');
      final epub = _link('EPUB');
      expect(folderPreferredLink([epub, fb2zip]), same(fb2zip));
    });

    test('no FB2 variants — EPUB preferred over PDF', () {
      final epub = _link('EPUB');
      final pdf = _link('PDF');
      expect(folderPreferredLink([pdf, epub]), same(epub));
    });

    test('no FB2, no EPUB — PDF preferred over MOBI', () {
      final pdf = _link('PDF');
      final mobi = _link('MOBI');
      expect(folderPreferredLink([mobi, pdf]), same(pdf));
    });

    test('no FB2, no EPUB, no PDF — MOBI returned', () {
      final mobi = _link('MOBI');
      final djvu = _link('DJVU');
      expect(folderPreferredLink([djvu, mobi]), same(mobi));
    });

    test('no priority match — first link returned', () {
      final first = _link('DJVU');
      final second = _link('AZW3');
      expect(folderPreferredLink([first, second]), same(first));
    });
  });

  // ── inferSeriesFromUrl ─────────────────────────────────────────────────────

  group('inferSeriesFromUrl', () {
    test('returns series value when present', () {
      final url = Uri.parse('http://example.com/feed?series=The+Wheel+of+Time');
      expect(inferSeriesFromUrl(url), 'The Wheel of Time');
    });

    test('returns null when series param absent', () {
      final url = Uri.parse('http://example.com/feed?author=Tolkien');
      expect(inferSeriesFromUrl(url), isNull);
    });

    test('returns null when series param is empty string', () {
      final url = Uri.parse('http://example.com/feed?series=');
      expect(inferSeriesFromUrl(url), isNull);
    });

    test('returns null for URL with no query params', () {
      final url = Uri.parse('http://example.com/feed');
      expect(inferSeriesFromUrl(url), isNull);
    });

    test('decodes percent-encoded characters', () {
      // series=%D0%92%D0%BE%D0%B9%D0%BD%D0%B0 → "Война"
      final url = Uri.parse(
        'http://example.com/feed?series=%D0%92%D0%BE%D0%B9%D0%BD%D0%B0',
      );
      expect(inferSeriesFromUrl(url), 'Война');
    });

    test('survives go-router encode/decode round-trip with Russian series', () {
      // Reproduces the in-app navigation chain:
      //   entry.url.toString()
      //   → Uri.encodeComponent()      (NavigationEntryTile.onTap)
      //   → embedded in '/browse?url=…' string
      //   → Uri.parse(route).queryParameters['url']   (go_router / app.dart)
      //   → Uri.parse(decodedString)
      //   → inferSeriesFromUrl()
      const rawUrlString =
          'https://example.com/opds/author?author=%3DTest&series=%D0%9A%D0%BE%D1%81%D0%BC%D0%BE%D0%BE%D0%BB%D1%83%D1%85%D0%B8&genre=';
      final originalUrl = Uri.parse(rawUrlString);

      final encodedParam = Uri.encodeComponent(originalUrl.toString());
      final routeUrl = '/browse?catalogId=1&url=$encodedParam&title=test';
      final decodedUrlString = Uri.parse(routeUrl).queryParameters['url']!;
      final reconstructedUrl = Uri.parse(decodedUrlString);

      expect(inferSeriesFromUrl(reconstructedUrl), 'Космоолухи');
    });
  });
}

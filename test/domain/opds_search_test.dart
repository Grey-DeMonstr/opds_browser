import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_search.dart';

void main() {
  SearchLink link(String url, [String? type]) =>
      SearchLink(url: Uri.parse(url), type: type);

  group('isOpenSearchDescription', () {
    test('reads the declared type', () {
      expect(
        isOpenSearchDescription(
          link(
            'https://example.com/opds/opensearch',
            'application/opensearchdescription+xml',
          ),
        ),
        isTrue,
      );
    });

    test('tolerates parameters and casing around the type', () {
      expect(
        isOpenSearchDescription(
          link(
            'https://example.com/o',
            'Application/OpenSearchDescription+XML; charset=utf-8',
          ),
        ),
        isTrue,
      );
    });

    test('an atom link is not a description document', () {
      expect(
        isOpenSearchDescription(
          link('https://example.com/s?q={searchTerms}', 'application/atom+xml'),
        ),
        isFalse,
      );
    });
  });

  group('isSearchTemplate', () {
    test('true when the href carries the macro', () {
      expect(
        isSearchTemplate(link('https://example.com/s?q={searchTerms}')),
        isTrue,
      );
    });

    test('false for a plain href', () {
      expect(isSearchTemplate(link('https://example.com/s')), isFalse);
    });

    test('recognises the macro after a Uri has encoded its braces', () {
      // resolveHref hands back a Uri, and Uri normalises { } to %7B %7D. A
      // template that survived that round trip is still a template.
      final resolved = Uri.parse(
        'https://example.com/opds',
      ).resolve('/s?q={searchTerms}');
      expect(resolved.toString(), contains('%7BsearchTerms%7D'));
      expect(isSearchTemplate(SearchLink(url: resolved)), isTrue);
    });
  });

  group('preferredSearchLink', () {
    test('no links means the catalogue cannot be searched', () {
      expect(preferredSearchLink(const []), isNull);
    });

    test('a direct template wins over a description document', () {
      // Step 1 of the design: substituting costs no round trip, so a
      // catalogue offering both is searched without fetching the document.
      final chosen = preferredSearchLink([
        link(
          'https://example.com/opensearch',
          'application/opensearchdescription+xml',
        ),
        link('https://example.com/s?q={searchTerms}', 'application/atom+xml'),
      ]);
      expect(
        searchTemplateOf(chosen!),
        'https://example.com/s?q={searchTerms}',
      );
    });

    test('falls back to the description document', () {
      final chosen = preferredSearchLink([
        link(
          'https://example.com/opensearch',
          'application/opensearchdescription+xml',
        ),
      ]);
      expect(chosen?.url.toString(), 'https://example.com/opensearch');
    });

    test('a link that is neither is not offered as a search', () {
      // Guessing a URL is what the design forbids: no macro and no
      // description document means there is nothing to substitute into.
      expect(
        preferredSearchLink([link('https://example.com/s', 'text/html')]),
        isNull,
      );
    });
  });

  group('searchTemplateOf', () {
    test('gives back the template as the catalogue wrote it', () {
      final resolved = Uri.parse(
        'https://example.com/opds',
      ).resolve('/s?q={searchTerms}');
      expect(
        searchTemplateOf(SearchLink(url: resolved)),
        'https://example.com/s?q={searchTerms}',
      );
    });
  });

  group('absoluteSearchTemplate', () {
    test('makes a relative template absolute against the document', () {
      // A description document routinely publishes a root-relative template.
      expect(
        absoluteSearchTemplate(
          Uri.parse('https://example.com/opds/opensearch'),
          '/opds/search?term={searchTerms}',
        ),
        'https://example.com/opds/search?term={searchTerms}',
      );
    });

    test('leaves an already absolute template alone', () {
      expect(
        absoluteSearchTemplate(
          Uri.parse('https://example.com/opds/opensearch'),
          'https://other.example/find?q={searchTerms}',
        ),
        'https://other.example/find?q={searchTerms}',
      );
    });
  });

  group('expandSearchTemplate', () {
    test('substitutes the terms', () {
      expect(
        expandSearchTemplate(
          'https://example.com/s?q={searchTerms}',
          'dickens',
        ).toString(),
        'https://example.com/s?q=dickens',
      );
    });

    test('percent-encodes as UTF-8', () {
      // Catalogues serving windows-1251 feeds still take UTF-8 query terms;
      // this is what the live probe of the reference catalogue confirmed.
      expect(
        expandSearchTemplate(
          'https://example.com/s?q={searchTerms}',
          'Толстой',
        ).toString(),
        'https://example.com/s?q=%D0%A2%D0%BE%D0%BB%D1%81%D1%82%D0%BE%D0%B9',
      );
    });

    test('encodes a space rather than leaving it raw', () {
      expect(
        expandSearchTemplate(
          'https://example.com/s?q={searchTerms}',
          'war and peace',
        ).toString(),
        'https://example.com/s?q=war%20and%20peace',
      );
    });

    test('drops the optional parameters the app does not supply', () {
      // OpenSearch marks these with a trailing `?`. Leaving the braces in
      // would send the macro to the server as a literal.
      expect(
        expandSearchTemplate(
          'https://example.com/s?q={searchTerms}&i={startIndex?}&c={count?}',
          'x',
        ).toString(),
        'https://example.com/s?q=x&i=&c=',
      );
    });

    test('empties a required parameter it cannot fill', () {
      expect(
        expandSearchTemplate(
          'https://example.com/s?q={searchTerms}&lang={language}',
          'x',
        ).toString(),
        'https://example.com/s?q=x&lang=',
      );
    });

    test('a template without the macro still yields a usable URL', () {
      expect(
        expandSearchTemplate('https://example.com/s', 'x').toString(),
        'https://example.com/s',
      );
    });
  });
}

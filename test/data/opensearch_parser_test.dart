import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/opds1/opensearch_parser.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  group('parseOpenSearchTemplate', () {
    test('reads the Url template', () {
      expect(
        parseOpenSearchTemplate(fixture('opensearch_description.xml')),
        '/opds/search?term={searchTerms}',
      );
    });

    test('prefers an atom Url over an html one', () {
      // A description document commonly offers a browser page first. Following
      // it would download HTML the feed parser cannot read.
      expect(
        parseOpenSearchTemplate(
          fixture('opensearch_description_html_first.xml'),
        ),
        'https://example.com/opds/find?q={searchTerms}&page={startPage?}',
      );
    });

    test('a document with no Url yields null', () {
      expect(
        parseOpenSearchTemplate(
          '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
          '<ShortName>x</ShortName></OpenSearchDescription>',
        ),
        isNull,
      );
    });

    test('a Url without a template is ignored', () {
      expect(
        parseOpenSearchTemplate(
          '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
          '<Url type="application/atom+xml"/></OpenSearchDescription>',
        ),
        isNull,
      );
    });

    test('malformed XML is a ParseException', () {
      expect(
        () => parseOpenSearchTemplate('<OpenSearchDescription>'),
        throwsA(isA<ParseException>()),
      );
    });

    test('a document that is not a description is a ParseException', () {
      expect(
        () => parseOpenSearchTemplate(
          '<feed xmlns="http://www.w3.org/2005/Atom"><title>x</title></feed>',
        ),
        throwsA(isA<ParseException>()),
      );
    });
  });
}

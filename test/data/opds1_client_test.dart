import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/opds1/opds1_client.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

// Minimal valid OPDS Atom feed used as the "happy path" response body.
final _validFeedBytes = utf8.encode(
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<feed xmlns="http://www.w3.org/2005/Atom">'
  '<title>Test Feed</title>'
  '<entry>'
  '<title>Sub-folder</title>'
  '<link rel="subsection" '
  'type="application/atom+xml;profile=opds-catalog" '
  'href="https://example.com/opds/sub"/>'
  '</entry>'
  '</feed>',
);

void main() {
  final feedUrl = Uri.parse('https://example.com/opds');

  group('Opds1Client.fetchFeed', () {
    test('returns ParsedFeed on 200 with valid OPDS XML', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(_validFeedBytes, 200),
      );
      final opds = Opds1Client(client);
      final feed = await opds.fetchFeed(feedUrl);
      expect(feed, isA<ParsedFeed>());
      expect(feed.title, 'Test Feed');
      expect(feed.entries.length, 1);
      expect(feed.entries.first, isA<NavigationEntry>());
    });

    test('throws HttpStatusException on 404', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      final opds = Opds1Client(client);
      expect(
        opds.fetchFeed(feedUrl),
        throwsA(
          isA<HttpStatusException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test('throws HttpStatusException on 401', () async {
      final client = MockClient(
        (_) async => http.Response('Unauthorized', 401),
      );
      final opds = Opds1Client(client);
      expect(
        opds.fetchFeed(feedUrl),
        throwsA(
          isA<HttpStatusException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });

    test('throws NetworkException on SocketException', () async {
      final client = MockClient((_) async {
        throw const SocketException('No route to host');
      });
      final opds = Opds1Client(client);
      expect(opds.fetchFeed(feedUrl), throwsA(isA<NetworkException>()));
    });

    test('throws ParseException when 200 body is not valid OPDS XML', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(utf8.encode('not xml at all'), 200),
      );
      final opds = Opds1Client(client);
      expect(opds.fetchFeed(feedUrl), throwsA(isA<ParseException>()));
    });
  });

  group('Opds1Client.probe', () {
    test('returns true for valid OPDS feed', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(_validFeedBytes, 200),
      );
      expect(await Opds1Client(client).probe(feedUrl), isTrue);
    });

    test('returns false when body is not parseable as OPDS', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(utf8.encode('not xml'), 200),
      );
      expect(await Opds1Client(client).probe(feedUrl), isFalse);
    });

    test('propagates NetworkException (not swallowed by probe)', () async {
      final client = MockClient((_) async {
        throw const SocketException('Connection refused');
      });
      expect(
        Opds1Client(client).probe(feedUrl),
        throwsA(isA<NetworkException>()),
      );
    });

    test('propagates HttpStatusException (not swallowed by probe)', () async {
      final client = MockClient((_) async => http.Response('Error', 500));
      expect(
        Opds1Client(client).probe(feedUrl),
        throwsA(isA<HttpStatusException>()),
      );
    });
  });

  group('Opds1Client.resolveSearchTemplate', () {
    SearchLink link(String url, [String? type]) =>
        SearchLink(url: Uri.parse(url), type: type);

    test('a templated link needs no request at all', () async {
      var called = false;
      final opds = Opds1Client(
        MockClient((_) async {
          called = true;
          return http.Response('', 500);
        }),
      );

      final template = await opds.resolveSearchTemplate(
        link('https://example.com/s?q={searchTerms}', 'application/atom+xml'),
      );

      expect(template, 'https://example.com/s?q={searchTerms}');
      expect(called, isFalse);
    });

    test(
      'a description document is fetched and its template resolved',
      () async {
        final opds = Opds1Client(
          MockClient(
            (_) async => http.Response.bytes(
              utf8.encode(
                '<?xml version="1.0" encoding="utf-8"?>'
                '<OpenSearchDescription '
                'xmlns="http://a9.com/-/spec/opensearch/1.1/">'
                '<Url type="application/atom+xml" '
                'template="/opds/search?term={searchTerms}"/>'
                '</OpenSearchDescription>',
              ),
              200,
            ),
          ),
        );

        final template = await opds.resolveSearchTemplate(
          link(
            'https://example.com/opds/opensearch',
            'application/opensearchdescription+xml',
          ),
        );

        // Relative in the document, absolute by the time anyone substitutes.
        expect(template, 'https://example.com/opds/search?term={searchTerms}');
      },
    );

    test('a link that is neither resolves to null without a request', () async {
      var called = false;
      final opds = Opds1Client(
        MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );

      expect(
        await opds.resolveSearchTemplate(
          link('https://example.com/s', 'text/html'),
        ),
        isNull,
      );
      expect(called, isFalse);
    });

    test('a description document holding no usable Url yields null', () async {
      final opds = Opds1Client(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              '<OpenSearchDescription '
              'xmlns="http://a9.com/-/spec/opensearch/1.1/">'
              '<ShortName>x</ShortName></OpenSearchDescription>',
            ),
            200,
          ),
        ),
      );

      expect(
        await opds.resolveSearchTemplate(
          link(
            'https://example.com/o',
            'application/opensearchdescription+xml',
          ),
        ),
        isNull,
      );
    });

    test('a failure reaching the document propagates', () async {
      // "Cannot be searched" and "could not be reached" must stay distinct.
      final opds = Opds1Client(
        MockClient((_) async => http.Response('nope', 503)),
      );

      expect(
        opds.resolveSearchTemplate(
          link(
            'https://example.com/o',
            'application/opensearchdescription+xml',
          ),
        ),
        throwsA(isA<HttpStatusException>()),
      );
    });
  });
}

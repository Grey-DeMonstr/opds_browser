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
      final client = MockClient((_) async =>
          http.Response.bytes(_validFeedBytes, 200));
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
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('throws HttpStatusException on 401', () async {
      final client = MockClient((_) async => http.Response('Unauthorized', 401));
      final opds = Opds1Client(client);
      expect(
        opds.fetchFeed(feedUrl),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
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
      final client = MockClient((_) async =>
          http.Response.bytes(utf8.encode('not xml at all'), 200));
      final opds = Opds1Client(client);
      expect(opds.fetchFeed(feedUrl), throwsA(isA<ParseException>()));
    });
  });

  group('Opds1Client.probe', () {
    test('returns true for valid OPDS feed', () async {
      final client = MockClient((_) async =>
          http.Response.bytes(_validFeedBytes, 200));
      expect(await Opds1Client(client).probe(feedUrl), isTrue);
    });

    test('returns false when body is not parseable as OPDS', () async {
      final client = MockClient((_) async =>
          http.Response.bytes(utf8.encode('not xml'), 200));
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
}

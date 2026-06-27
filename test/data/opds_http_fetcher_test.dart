import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/opds_http_fetcher.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  final feedUrl = Uri.parse('https://example.com/opds');
  final minimalBody = utf8.encode('<?xml version="1.0"?><feed/>');

  group('OpdsHttpFetcher', () {
    test('returns body bytes on 200', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(minimalBody, 200),
      );
      final result = await OpdsHttpFetcher(client).fetch(feedUrl);
      expect(result, minimalBody);
    });

    test('sends User-Agent header', () async {
      String? userAgent;
      final client = MockClient((req) async {
        userAgent = req.headers['User-Agent'];
        return http.Response.bytes(minimalBody, 200);
      });
      await OpdsHttpFetcher(client).fetch(feedUrl);
      expect(userAgent, 'OpdsBrowser/1.0');
    });

    test('throws HttpStatusException(404) on 404', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      expect(
        OpdsHttpFetcher(client).fetch(feedUrl),
        throwsA(
          isA<HttpStatusException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test('throws HttpStatusException(401) on 401', () async {
      final client = MockClient(
        (_) async => http.Response('Unauthorized', 401),
      );
      expect(
        OpdsHttpFetcher(client).fetch(feedUrl),
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
        throw const SocketException('Connection refused');
      });
      expect(
        OpdsHttpFetcher(client).fetch(feedUrl),
        throwsA(isA<NetworkException>()),
      );
    });

    test('throws NetworkException on timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response.bytes(minimalBody, 200);
      });
      expect(
        OpdsHttpFetcher(
          client,
          timeout: const Duration(milliseconds: 100),
        ).fetch(feedUrl),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}

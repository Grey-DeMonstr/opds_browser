import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/opds_client.dart';

void main() {
  group('OpdsException hierarchy', () {
    test('NetworkException stores message and is an OpdsException', () {
      const e = NetworkException('no connection');
      expect(e.message, 'no connection');
      expect(e, isA<OpdsException>());
      expect(e, isA<Exception>());
    });

    test('HttpStatusException stores statusCode and message', () {
      const e = HttpStatusException(404, 'not found');
      expect(e.statusCode, 404);
      expect(e.message, 'not found');
      expect(e, isA<OpdsException>());
    });

    test('ParseException stores message', () {
      const e = ParseException('bad xml');
      expect(e.message, 'bad xml');
      expect(e, isA<OpdsException>());
    });

    test('UnsupportedProtocolException stores message', () {
      const e = UnsupportedProtocolException('not opds');
      expect(e.message, 'not opds');
      expect(e, isA<OpdsException>());
    });
  });
}

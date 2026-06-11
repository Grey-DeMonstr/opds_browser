import 'package:opds_browser/domain/models.dart';

abstract interface class OpdsClient {
  Future<ParsedFeed> fetchFeed(Uri url);

  /// Returns true if [url] responds with a valid OPDS feed, false if reachable
  /// but not OPDS. Throws [NetworkException] on connection failure.
  Future<bool> probe(Uri url);
}

sealed class OpdsException implements Exception {
  final String message;
  const OpdsException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkException extends OpdsException {
  const NetworkException(super.message);
}

class HttpStatusException extends OpdsException {
  final int statusCode;
  const HttpStatusException(this.statusCode, super.message);

  @override
  String toString() => 'HttpStatusException($statusCode): $message';
}

class ParseException extends OpdsException {
  const ParseException(super.message);
}

class UnsupportedProtocolException extends OpdsException {
  const UnsupportedProtocolException(super.message);
}

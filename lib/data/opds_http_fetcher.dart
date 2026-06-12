import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:opds_browser/domain/opds_client.dart';

class OpdsHttpFetcher {
  final http.Client _client;
  final Duration _timeout;

  OpdsHttpFetcher(this._client, {this._timeout = const Duration(seconds: 20)});

  Future<List<int>> fetch(Uri url) async {
    try {
      final response = await _client
          .get(url, headers: const {'User-Agent': 'OpdsBrowser/1.0'})
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpStatusException(
          response.statusCode,
          'HTTP ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw NetworkException('Request timed out after ${_timeout.inSeconds}s');
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    }
  }
}

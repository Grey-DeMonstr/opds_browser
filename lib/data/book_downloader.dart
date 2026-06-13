import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

class BookDownloader {
  BookDownloader(this._client, this._storage);

  final http.Client _client;
  final DownloadStorage _storage;

  static const _alreadyExists = 'already_exists';

  Future<String> download(
    BookEntry entry,
    AcquisitionLink link,
    AppSettings settings,
  ) async {
    final segments = buildPathSegments(settings, entry);
    final fileName = buildFileName(entry, link, settings);

    if (await _storage.exists(segments, fileName)) {
      return _alreadyExists;
    }

    late http.StreamedResponse response;
    try {
      final request = http.Request('GET', link.url)
        ..headers['User-Agent'] = 'OpdsBrowser/1.0';
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on TimeoutException {
      throw const NetworkException('Connection timed out');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpStatusException(
        response.statusCode,
        'HTTP ${response.statusCode}',
      );
    }

    return _storage.write(segments, fileName, response.stream);
  }
}

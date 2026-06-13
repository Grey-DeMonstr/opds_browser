import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/data/book_downloader.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';
import 'package:opds_browser/domain/repositories.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;
  final String writeResult;
  String? writtenFileName;
  List<String>? writtenSegments;

  FakeDownloadStorage({
    this.existsResult = false,
    this.writeResult = 'content://fake/1',
  });

  @override
  Future<bool> exists(List<String> pathSegments, String fileName) async =>
      existsResult;

  @override
  Future<String> write(
    List<String> pathSegments,
    String fileName,
    Stream<List<int>> bytes,
  ) async {
    writtenFileName = fileName;
    writtenSegments = pathSegments;
    await bytes.drain<void>();
    return writeResult;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

final _link = AcquisitionLink(
  url: Uri.parse('https://example.com/book.fb2'),
  mimeType: 'application/fb2',
  formatLabel: 'FB2',
);

final _book = BookEntry(
  title: 'Book Title',
  authors: ['Jane Doe'],
  acquisitionLinks: [_link],
);

const _settings = AppSettings(target: SystemDownloads());

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('file already exists — returns "already_exists" without HTTP call', () async {
    var httpCalled = false;
    final client = MockClient((_) async {
      httpCalled = true;
      return http.Response('', 200);
    });
    final storage = FakeDownloadStorage(existsResult: true);
    final downloader = BookDownloader(client, storage);

    final result = await downloader.download(_book, _link, _settings);

    expect(result, 'already_exists');
    expect(httpCalled, isFalse);
  });

  test('successful download — correct fileName and segments passed to storage', () async {
    final client = MockClient(
      (_) async => http.Response.bytes([1, 2, 3], 200),
    );
    final storage = FakeDownloadStorage(writeResult: 'content://uri/123');
    final downloader = BookDownloader(client, storage);

    final result = await downloader.download(_book, _link, _settings);

    expect(result, 'content://uri/123');
    expect(storage.writtenFileName, buildFileName(_book, _link, _settings));
    expect(storage.writtenSegments, isEmpty);
  });

  test('non-2xx response throws HttpStatusException', () async {
    final client = MockClient((_) async => http.Response('Not found', 404));
    final storage = FakeDownloadStorage();
    final downloader = BookDownloader(client, storage);

    await expectLater(
      downloader.download(_book, _link, _settings),
      throwsA(
        isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('SocketException throws NetworkException', () async {
    final client = MockClient(
      (_) async => throw const SocketException('Network is unreachable'),
    );
    final storage = FakeDownloadStorage();
    final downloader = BookDownloader(client, storage);

    await expectLater(
      downloader.download(_book, _link, _settings),
      throwsA(isA<NetworkException>()),
    );
  });

  test('path segments include author folder when flag is on', () async {
    final client = MockClient((_) async => http.Response.bytes([1], 200));
    final storage = FakeDownloadStorage();
    final downloader = BookDownloader(client, storage);
    const settings = AppSettings(
      target: SystemDownloads(),
      createAuthorFolder: true,
    );

    await downloader.download(_book, _link, settings);

    expect(storage.writtenSegments, ['Jane Doe']);
  });
}

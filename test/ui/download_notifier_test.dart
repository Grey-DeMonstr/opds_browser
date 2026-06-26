import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;
  final String writeResult;
  String? writtenMimeType;
  List<String>? writtenSegments;

  FakeDownloadStorage({
    this.existsResult = false,
    this.writeResult = 'content://fake/1',
  });

  @override
  Future<bool> exists(List<String> p, String f) async => existsResult;

  @override
  Future<String> write(
      List<String> p, String f, Stream<List<int>> b, String mimeType) async {
    writtenMimeType = mimeType;
    writtenSegments = p;
    await b.drain<void>();
    return writeResult;
  }
}

// ── Container builder ─────────────────────────────────────────────────────────

ProviderContainer _makeContainer({
  required MockClient client,
  FakeDownloadStorage? storage,
  bool storageExists = false,
  String storageWriteResult = 'content://fake/1',
}) {
  final s = storage ??
      FakeDownloadStorage(
        existsResult: storageExists,
        writeResult: storageWriteResult,
      );
  final c = ProviderContainer(overrides: [
    httpClientProvider.overrideWith((ref) => client),
    downloadStorageProvider.overrideWith((ref) => s),
  ]);
  addTearDown(c.dispose);
  return c;
}

// ── Test data ─────────────────────────────────────────────────────────────────

final _linkUrl = Uri.parse('https://example.com/book.fb2');

final _book = BookEntry(
  title: 'Book Title',
  authors: ['Jane Doe'],
  acquisitionLinks: [
    AcquisitionLink(
      url: _linkUrl,
      mimeType: 'application/fb2',
      formatLabel: 'FB2',
    ),
  ],
);

const _settings = AppSettings(target: SystemDownloads());

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('initial state is DownloadIdle', () {
    final c = _makeContainer(client: MockClient((_) async => http.Response('', 200)));
    expect(c.read(downloadNotifierProvider(_linkUrl)), isA<DownloadIdle>());
  });

  test('start() transitions to DownloadDone on success', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      storageWriteResult: 'content://result/42',
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final state = c.read(downloadNotifierProvider(_linkUrl));
    expect(state, isA<DownloadDone>());
    final done = state as DownloadDone;
    expect(done.alreadyExisted, isFalse);
    expect(done.contentUri, 'content://result/42');
    expect(done.fileName, isNotEmpty);
  });

  test('start() with already-existing file → DownloadDone(alreadyExisted: true)', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response('', 200)),
      storageExists: true,
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final done = c.read(downloadNotifierProvider(_linkUrl)) as DownloadDone;
    expect(done.alreadyExisted, isTrue);
    expect(done.contentUri, '');
  });

  test('start() with non-2xx response → DownloadFailed', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response('Not found', 404)),
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    expect(c.read(downloadNotifierProvider(_linkUrl)), isA<DownloadFailed>());
    final failed = c.read(downloadNotifierProvider(_linkUrl)) as DownloadFailed;
    expect(failed.message, contains('404'));
  });

  test('start() is a no-op when already DownloadInProgress', () async {
    var callCount = 0;
    final completer = Completer<http.Response>();
    final c = _makeContainer(
      client: MockClient((_) {
        callCount++;
        return completer.future;
      }),
    );

    final notifier = c.read(downloadNotifierProvider(_linkUrl).notifier);
    // Kick off first download — does not await (it's waiting for completer)
    final firstFuture = notifier.start(_book, _settings);
    // Yield so the first start() can run up to the await point
    await Future<void>.delayed(Duration.zero);
    expect(c.read(downloadNotifierProvider(_linkUrl)), isA<DownloadInProgress>());

    // Second call — should be no-op
    await notifier.start(_book, _settings);
    expect(callCount, 1);

    // Let the first download finish
    completer.complete(http.Response.bytes([1], 200));
    await firstFuture;
  });

  test('DownloadDone.mimeType matches link mimeType on success', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final done = c.read(downloadNotifierProvider(_linkUrl)) as DownloadDone;
    expect(done.mimeType, 'application/fb2');
  });

  test('lastDownloadResultProvider is set on successful completion', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    expect(c.read(lastDownloadResultProvider), isA<DownloadDone>());
  });

  test('lastDownloadResultProvider is set when file already existed', () async {
    final c = _makeContainer(
      client: MockClient((_) async => http.Response('', 200)),
      storageExists: true,
    );

    await c.read(downloadNotifierProvider(_linkUrl).notifier).start(_book, _settings);

    final result = c.read(lastDownloadResultProvider);
    expect(result, isA<DownloadDone>());
    expect((result as DownloadDone).alreadyExisted, isTrue);
  });

  test('start() with inferredSeries — inferred series used for path segments when createSeriesFolder is true', () async {
    final storage = FakeDownloadStorage(writeResult: 'content://result');
    final c = _makeContainer(
      client: MockClient((_) async => http.Response.bytes([1], 200)),
      storage: storage,
    );
    const settings = AppSettings(
      target: SystemDownloads(),
      createSeriesFolder: true,
    );

    await c
        .read(downloadNotifierProvider(_linkUrl).notifier)
        .start(_book, settings, inferredSeries: 'My Series');

    expect(storage.writtenSegments, ['My Series']);
  });
}

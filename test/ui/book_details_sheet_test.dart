import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;

  FakeDownloadStorage({this.existsResult = false});

  @override
  Future<bool> exists(List<String> p, String f) async => existsResult;

  @override
  Future<String> write(
      List<String> p, String f, Stream<List<int>> b, String mimeType) async {
    await b.drain<void>();
    return 'content://fake/1';
  }
}

// ── Fake settings notifier ────────────────────────────────────────────────────

class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  FakeSettingsNotifier({this._initial = const AppSettings(target: SystemDownloads())});

  @override
  Future<AppSettings> build() async => _initial;
}

// ── Helper ────────────────────────────────────────────────────────────────────

AcquisitionLink _link(String label) => AcquisitionLink(
      url: Uri.parse('https://example.com/${label.toLowerCase()}'),
      mimeType: 'application/octet-stream',
      formatLabel: label,
    );

Widget _buildApp({
  required BookEntry entry,
  required MockClient mockClient,
  bool storageExists = false,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => FakeSettingsNotifier()),
      httpClientProvider.overrideWith((ref) => mockClient),
      downloadStorageProvider.overrideWith(
        (ref) => FakeDownloadStorage(existsResult: storageExists),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: BookDetailsSheet(entry: entry)),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('BookDetailsSheet rendering', () {
    testWidgets('renders title, authors, series, and summary', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        series: 'Great Series',
        seriesIndex: 1.0,
        summary: 'A great summary.',
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Book Title'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Great Series #1'), findsOneWidget);
      expect(find.text('A great summary.'), findsOneWidget);
    });

    testWidgets('renders cover placeholder when no coverUrl', (tester) async {
      final entry = BookEntry(
        title: 'T',
        authors: [],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.book), findsWidgets);
    });
  });

  group('Download button — direct download (FB2.ZIP present)', () {
    testWidgets('tapping Download starts download without showing picker',
        (tester) async {
      var httpCalled = false;
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('FB2.ZIP')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async {
            httpCalled = true;
            return http.Response.bytes([1, 2, 3], 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(httpCalled, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Download button — format picker (no FB2)', () {
    testWidgets('tapping Download shows "Choose format" dialog', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.text('Choose format'), findsOneWidget);
      expect(find.text('EPUB'), findsWidgets);
      expect(find.text('PDF'), findsWidgets);
    });

    testWidgets('choosing a format from picker starts download', (tester) async {
      var httpCalled = false;
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async {
            httpCalled = true;
            return http.Response.bytes([1, 2, 3], 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      // Tap EPUB in the dialog
      await tester.tap(find.text('EPUB').last);
      await tester.pumpAndSettle();

      expect(httpCalled, isTrue);
    });
  });

  group('Secondary format rows', () {
    testWidgets('preferred format absent; other formats shown', (tester) async {
      // FB2 is preferred → must NOT appear as a secondary row.
      // EPUB and PDF are "the other formats" per spec §9.1 and must be shown.
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2'), _link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FB2'), findsNothing);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('FB2.ZIP preferred — FB2 still listed as secondary row',
        (tester) async {
      // When both FB2.ZIP and FB2 are present, FB2.ZIP is preferred (auto-selected).
      // FB2 is "the other format" and must remain as a secondary row.
      // FB2.ZIP itself must NOT appear in secondary rows.
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2.ZIP'), _link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FB2.ZIP'), findsNothing);
      expect(find.text('FB2'), findsOneWidget);
    });

    testWidgets('no preferred (EPUB+PDF): all formats shown as secondary rows',
        (tester) async {
      // No FB2 variant → preferred is null → picker dialog on Download tap.
      // All formats must still be visible as secondary tap-to-download rows.
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('EPUB'), _link('PDF')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('tapping a secondary row starts download for that format',
        (tester) async {
      Uri? requestedUrl;
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2'), _link('EPUB')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((request) async {
            requestedUrl = request.url;
            return http.Response.bytes([1], 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EPUB'));
      await tester.pumpAndSettle();

      expect(requestedUrl?.toString(), contains('epub'));
    });
  });

  group('DownloadInProgress state', () {
    testWidgets('spinner replaces Download button while downloading', (tester) async {
      final completer = Completer<http.Response>();
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) => completer.future),
        ),
      );
      await tester.pumpAndSettle();

      // Tap and pump once (not settle) so we catch the in-progress state
      // before the completer resolves.
      await tester.tap(find.text('Download'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      completer.complete(http.Response.bytes([1], 200));
      await tester.pumpAndSettle();
    });
  });

  group('DownloadFailed snackbar', () {
    testWidgets('shows error snackbar with Retry action on failure', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response('Error', 500)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

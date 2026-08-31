import 'dart:async';
import 'dart:io';

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
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/filter_chip_bar.dart';

// ── Fake storage ──────────────────────────────────────────────────────────────

class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;

  FakeDownloadStorage({this.existsResult = false});

  @override
  Future<bool> exists(List<String> p, String f) async => existsResult;

  @override
  Future<String> write(
    List<String> p,
    String f,
    Stream<List<int>> b,
    String mimeType,
  ) async {
    await b.drain<void>();
    return 'content://fake/1';
  }
}

// ── Fake settings notifier ────────────────────────────────────────────────────

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier({this.initial = _configured});

  final AppSettings initial;

  static const _configured = AppSettings(
    target: CustomSafFolder('content://example', 'Folder'),
  );

  int pickCalls = 0;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<bool> pickCustomFolder() async {
    pickCalls++;
    state = AsyncData(_configured);
    return true;
  }
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
  SettingsNotifier? settingsNotifier,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => settingsNotifier ?? FakeSettingsNotifier(),
      ),
      httpClientProvider.overrideWith((ref) => mockClient),
      downloadStorageProvider.overrideWith(
        (ref) => FakeDownloadStorage(existsResult: storageExists),
      ),
    ],
    child: MaterialApp(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: Scaffold(body: BookDetailsSheet(entry: entry)),
    ),
  );
}

/// Opens the sheet through the same entry point the browse screen uses, so
/// these tests cover how it is actually presented.
Widget _openInModalSheet({required BookEntry entry, required Size screenSize}) {
  return MediaQuery(
    data: MediaQueryData(size: screenSize),
    child: ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => FakeSettingsNotifier()),
        httpClientProvider.overrideWith(
          (ref) => MockClient((_) async => http.Response.bytes([1], 200)),
        ),
        downloadStorageProvider.overrideWith(
          (ref) => FakeDownloadStorage(existsResult: false),
        ),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBookDetailsSheet(context, entry),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('BookDetailsSheet rendering', () {
    testWidgets('sheet content is inset above the system navigation bar', (
      tester,
    ) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(bottom: 48),
            viewPadding: EdgeInsets.only(bottom: 48),
          ),
          child: ProviderScope(
            overrides: [
              settingsProvider.overrideWith(() => FakeSettingsNotifier()),
              httpClientProvider.overrideWith(
                (ref) => MockClient((_) async => http.Response.bytes([1], 200)),
              ),
              downloadStorageProvider.overrideWith(
                (ref) => FakeDownloadStorage(existsResult: false),
              ),
            ],
            child: MaterialApp(
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => BookDetailsSheet(entry: entry),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final bottom = tester.getRect(find.byType(SingleChildScrollView)).bottom;
      expect(bottom, lessThanOrEqualTo(600 - 48));
    });

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

    testWidgets('a long summary is reachable in full behind Show more', (
      tester,
    ) async {
      final longSummary = List.generate(
        60,
        (i) => 'Sentence number $i about the whale.',
      ).join(' ');
      final entry = BookEntry(
        title: 'Moby Dick; Or, The Whale',
        authors: ['Melville, Herman'],
        summary: longSummary,
        acquisitionLinks: [_link('EPUB')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      // Turn 4 clamps it; Show more is what makes the whole text available.
      expect(
        tester.widget<Text>(find.byKey(const Key('book-blurb'))).maxLines,
        6,
      );
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.byKey(const Key('book-blurb')));
      expect(text.maxLines, isNull);
      expect(text.data, longSummary);
    });

    testWidgets('a long summary does not push the actions out of reach', (
      tester,
    ) async {
      final longSummary = List.generate(
        60,
        (i) => 'Sentence number $i about the whale.',
      ).join(' ');
      final entry = BookEntry(
        title: 'Moby Dick; Or, The Whale',
        authors: ['Melville, Herman'],
        summary: longSummary,
        acquisitionLinks: [_link('EPUB'), _link('MOBI')],
      );

      await tester.pumpWidget(
        _openInModalSheet(entry: entry, screenSize: const Size(400, 600)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The panel scrolls rather than overflowing, so everything below the
      // summary — the Download button and the format list — stays reachable.
      await tester.scrollUntilVisible(find.text('MOBI'), 200);
      expect(find.text('MOBI'), findsOneWidget);
      expect(find.text('Download EPUB'), findsOneWidget);
    });

    testWidgets('the panel is swipable, with a drag handle', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        summary: 'A great summary.',
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _openInModalSheet(entry: entry, screenSize: const Size(400, 600)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.showDragHandle, isTrue);
      expect(sheet.enableDrag, isTrue);
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

      expect(find.byIcon(Icons.book_outlined), findsWidgets);
    });
  });

  group('Header — from Atom fields', () {
    testWidgets('categories render as tags', (tester) async {
      final entry = BookEntry(
        title: 'Профессия: ведьма',
        authors: ['Громыко Ольга'],
        categories: const ['Фэнтези', 'Юмористическая фантастика'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Фэнтези'), findsOneWidget);
      expect(find.text('Юмористическая фантастика'), findsOneWidget);
    });

    testWidgets('an entry with no categories shows no tag row', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book-tags')), findsNothing);
    });
  });

  group('Formats — one button, the rest as chips', () {
    testWidgets('the button names the format it will fetch', (tester) async {
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

      expect(find.text('Download FB2.ZIP'), findsOneWidget);
    });

    testWidgets('the remaining formats are chips, the chosen one is not', (
      tester,
    ) async {
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

      expect(find.text('Download FB2'), findsOneWidget);
      expect(find.text('FB2'), findsNothing);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('a lone format leaves no chip row behind', (tester) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('or'), findsNothing);
    });

    testWidgets('with no FB2 variant the button still names a format', (
      tester,
    ) async {
      // The old build had no preferred link here and opened a picker dialog.
      // Now the first by preference is simply the button.
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        acquisitionLinks: [_link('PDF'), _link('EPUB')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Download EPUB'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('tapping the button downloads without a picker', (
      tester,
    ) async {
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

      await tester.tap(find.text('Download FB2.ZIP'));
      await tester.pumpAndSettle();

      expect(httpCalled, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('tapping a chip downloads that format', (tester) async {
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

  group('Content — rule 1, headings split blurb from Details', () {
    BookEntry entryWithHeadings() => BookEntry(
      title: 'Профессия: ведьма',
      authors: ['Громыко Ольга'],
      contentHtml: File(
        'test/fixtures/content_with_headings.html',
      ).readAsStringSync(),
      acquisitionLinks: [_link('FB2')],
    );

    testWidgets('the blurb shows, the facts do not', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithHeadings(),
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Каждый здравомыслящий человек'),
        findsOneWidget,
      );
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('ISBN'), findsNothing);
    });

    testWidgets('expanding Details reveals sections and rows', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithHeadings(),
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      // The blurb is long enough to push the disclosure past the viewport.
      await tester.scrollUntilVisible(find.text('Details'), 200);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('ISBN'), 200);
      expect(find.text('ISBN'), findsOneWidget);
      expect(find.text('5-93556-247-2 , 978-5-9922-0105-5'), findsOneWidget);
    });

    testWidgets('there is no Show more affordance in this mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithHeadings(),
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Show more'), findsNothing);
    });
  });

  group('Content — rule 2, no headings', () {
    BookEntry entryWithoutHeadings() => BookEntry(
      title: 'Moby Dick; Or, The Whale',
      authors: ['Melville, Herman'],
      contentHtml: File(
        'test/fixtures/content_no_headings.html',
      ).readAsStringSync(),
      acquisitionLinks: [_link('EPUB')],
    );

    testWidgets('Details never appears', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithoutHeadings(),
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsNothing);
    });

    testWidgets('the text is clamped to six lines behind Show more', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithoutHeadings(),
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      final clamped = tester.widget<Text>(find.byKey(const Key('book-blurb')));
      expect(clamped.maxLines, 6);
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('Show more unclamps it and offers Show less', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithoutHeadings(),
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      final expanded = tester.widget<Text>(find.byKey(const Key('book-blurb')));
      expect(expanded.maxLines, isNull);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('a plain-text summary with no markup still shows', (
      tester,
    ) async {
      final entry = BookEntry(
        title: 'Book Title',
        authors: ['Jane Doe'],
        summary: 'A plain summary.',
        acquisitionLinks: [_link('FB2')],
      );

      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A plain summary.'), findsOneWidget);
      expect(find.text('Details'), findsNothing);
    });
  });

  group('DownloadInProgress state', () {
    testWidgets('spinner replaces the button while downloading', (
      tester,
    ) async {
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

      await tester.tap(find.text('Download FB2'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Download FB2'), findsNothing);

      completer.complete(http.Response.bytes([1], 200));
      await tester.pumpAndSettle();
    });
  });

  group('DownloadFailed snackbar', () {
    testWidgets('shows error snackbar with Retry action on failure', (
      tester,
    ) async {
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

      await tester.tap(find.text('Download FB2'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('library folder gate', () {
    final entry = BookEntry(
      title: 'Book Title',
      authors: ['Jane Doe'],
      acquisitionLinks: [_link('FB2')],
    );

    testWidgets('Download asks for a folder when none is set', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response('Error', 500)),
          settingsNotifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download FB2'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a library folder'), findsOneWidget);
      expect(find.textContaining('Download failed'), findsNothing);
    });

    testWidgets('Download proceeds once a folder is picked', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(
        _buildApp(
          entry: entry,
          mockClient: MockClient((_) async => http.Response('Error', 500)),
          settingsNotifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download FB2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();

      expect(notifier.pickCalls, 1);
      expect(find.textContaining('Download failed'), findsOneWidget);
    });
  });

  /// The sheet draws two rules, and they are not the same rule. The one under
  /// the actions is a zone boundary — the fixed head of the sheet against the
  /// description scrolling below it — and reads at the weight browse and
  /// search give that same boundary. The Details border is a rule inside a
  /// zone, and stays the lighter of the two.
  group('the sheet keeps the two rule weights apart', () {
    BookEntry entryWithDetails() => BookEntry(
      title: 'Book Title',
      authors: ['Jane Doe'],
      summary: 'A summary.',
      acquisitionLinks: [_link('FB2')],
    );

    testWidgets('the boundary under the actions carries the heavier rule', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          entry: entryWithDetails(),
          mockClient: MockClient((_) async => http.Response('', 404)),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(FadingRule),
          matching: find.byType(Container),
        ),
      );
      final gradient =
          (container.decoration! as BoxDecoration).gradient! as LinearGradient;

      expect(
        gradient.colors[1],
        buildLightTheme().extension<AppPalette>()!.rule,
      );
    });

    testWidgets('the Details border stays the lighter one', (tester) async {
      // Details appears only when the description carries headings to split
      // the facts out of, so this one needs the richer fixture.
      await tester.pumpWidget(
        _buildApp(
          entry: BookEntry(
            title: 'Book Title',
            authors: ['Jane Doe'],
            contentHtml: File(
              'test/fixtures/content_with_headings.html',
            ).readAsStringSync(),
            acquisitionLinks: [_link('FB2')],
          ),
          mockClient: MockClient((_) async => http.Response('', 404)),
        ),
      );
      await tester.pumpAndSettle();

      final palette = buildLightTheme().extension<AppPalette>()!;
      final bordered = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).border?.top.color ==
                    palette.hairline,
          );

      expect(bordered, isNotEmpty, reason: 'the Details rule is a hairline');
    });
  });
}

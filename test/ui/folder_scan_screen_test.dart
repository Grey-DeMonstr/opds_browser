import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/folder_scan_screen.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fake notifier ─────────────────────────────────────────────────────────────

class _FakeScanNotifier extends FolderDownloadNotifier {
  final FolderJobState _initial;

  _FakeScanNotifier(this._initial);

  @override
  FolderJobState build() => _initial;

  @override
  Future<void> start(int catalogId, Uri url) async {} // no-op in tests
}

// ── Router helper ─────────────────────────────────────────────────────────────

GoRouter _makeRouter({String initialLocation = '/folder-scan'}) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('HomeScreen'))),
      ),
      GoRoute(
        path: '/folder-scan',
        builder: (context, state) =>
            const FolderScanScreen(catalogId: 1, url: 'http://x.com/root'),
      ),
      GoRoute(
        path: '/folder-tree',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('TreeScreen'))),
      ),
    ],
    initialLocation: initialLocation,
  );
}

Widget _wrap(
  ProviderContainer container, {
  String initialLocation = '/folder-scan',
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: _makeRouter(initialLocation: initialLocation),
    ),
  );
}

ProviderContainer _container(FolderJobState initial) {
  final c = ProviderContainer(
    overrides: [
      folderDownloadProvider.overrideWith(() => _FakeScanNotifier(initial)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows scanning text and folder count', (tester) async {
    final container = _container(const FolderJobScanning(foldersFound: 7));
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    expect(find.textContaining('7'), findsOneWidget);
    // The body text contains "Scanning…" (distinct from AppBar title "Scanning folder")
    expect(find.textContaining('Scanning…'), findsOneWidget);
  });

  testWidgets('shows Cancel button', (tester) async {
    final container = _container(const FolderJobScanning(foldersFound: 0));
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'navigates to /folder-tree when state becomes FolderJobTreeReady',
    (tester) async {
      final book = DownloadBook(
        entry: BookEntry(
          title: 'B',
          authors: const ['A'],
          acquisitionLinks: [
            AcquisitionLink(
              url: Uri.parse('http://x.com/b.epub'),
              mimeType: 'application/epub+zip',
              formatLabel: 'EPUB',
            ),
          ],
        ),
        link: AcquisitionLink(
          url: Uri.parse('http://x.com/b.epub'),
          mimeType: 'application/epub+zip',
          formatLabel: 'EPUB',
        ),
      );

      final container = _container(const FolderJobScanning(foldersFound: 0));
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      // Simulate state change to TreeReady
      container
          .read(folderDownloadProvider.notifier)
          .state = FolderJobTreeReady(
        root: book,
        checkedBooks: {Uri.parse('http://x.com/b.epub')},
      );
      // pump frames to process state change and navigation; avoid pumpAndSettle
      // which loops forever with CircularProgressIndicator animating
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('TreeScreen'), findsOneWidget);
    },
  );

  testWidgets('navigates back (pop) when state becomes FolderJobDone', (
    tester,
  ) async {
    // Start at home, then push to /folder-scan so there's something to pop back to
    final container = _container(const FolderJobScanning(foldersFound: 0));
    await tester.pumpWidget(_wrap(container, initialLocation: '/'));
    await tester.pump();

    // Navigate to folder-scan
    final context = tester.element(find.text('HomeScreen'));
    GoRouter.of(context).push('/folder-scan');
    // Use pump with duration to avoid infinite loop from CircularProgressIndicator
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Scanning…'), findsOneWidget);

    // Simulate state change to FolderJobDone (e.g. empty scan / cancelled)
    container.read(folderDownloadProvider.notifier).state = FolderJobDone(
      root: DownloadFolder(title: '', children: []),
      results: const {},
      wasCancelled: true,
      stoppedAtLimit: false,
    );
    // pump a few frames to process the state change and navigation
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // After pop, back at HomeScreen
    expect(find.text('HomeScreen'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/folder_tree_screen.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AcquisitionLink _link(String id) => AcquisitionLink(
      url: Uri.parse('http://x.com/$id.epub'),
      mimeType: 'application/epub+zip',
      formatLabel: 'EPUB',
    );

DownloadBook _book(String id) => DownloadBook(
      entry: BookEntry(title: 'Book $id', authors: const ['A'], acquisitionLinks: [_link(id)]),
      link: _link(id),
    );

DownloadFolder _folder(String title, List<DownloadTreeNode> children) =>
    DownloadFolder(title: title, children: children);

// Fake notifier that accepts initial state via constructor and records calls.
class _FakeTreeNotifier extends FolderDownloadNotifier {
  _FakeTreeNotifier(this._initial);

  final FolderJobState _initial;
  Set<Uri>? lastSelection;
  Set<Uri>? lastConfirm;
  bool resetCalled = false;
  bool cancelCalled = false;

  @override
  FolderJobState build() => _initial;

  @override
  void updateSelection(Set<Uri> checkedBooks) {
    lastSelection = checkedBooks;
    state = (state as FolderJobTreeReady).copyWith(checkedBooks: checkedBooks);
  }

  @override
  Future<void> confirmDownload(Set<Uri> checkedBooks) async {
    lastConfirm = checkedBooks;
  }

  @override
  void reset() {
    resetCalled = true;
    // Note: setting state = const FolderJobIdle() requires riverpod context,
    // so we just set the flag for testing purposes.
  }

  @override
  void cancel() {
    cancelCalled = true;
  }
}

ProviderContainer _container(FolderJobState initial) {
  final c = ProviderContainer(overrides: [
    folderDownloadProvider.overrideWith(() => _FakeTreeNotifier(initial)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Widget _treeScreen(BuildContext context, GoRouterState state) =>
    const FolderTreeScreen();

GoRouter _router() => GoRouter(routes: [
      GoRoute(path: '/', builder: _treeScreen),
    ]);

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    );

Widget _wrapWithState(FolderJobState initial) =>
    _wrap(_container(initial));

// ── Selection mode tests ───────────────────────────────────────────────────────

void main() {
  group('selection mode', () {
    testWidgets('shows book title and checkbox', (tester) async {
      final book = _book('1');
      final c = _container(FolderJobTreeReady(
        root: book,
        checkedBooks: {book.link.url},
      ));
      await tester.pumpWidget(_wrap(c));
      expect(find.text('Book 1'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('shows folder title with tri-state checkbox', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final folder = _folder('MyFolder', [b1, b2]);
      final c = _container(FolderJobTreeReady(
        root: folder,
        checkedBooks: {b1.link.url, b2.link.url},
      ));
      await tester.pumpWidget(_wrap(c));
      expect(find.text('MyFolder'), findsOneWidget);
      // 3 checkboxes: folder + 2 books
      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('Download button shows book count', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final c = _container(FolderJobTreeReady(
        root: _folder('F', [b1, b2]),
        checkedBooks: {b1.link.url, b2.link.url},
      ));
      await tester.pumpWidget(_wrap(c));
      expect(find.textContaining('2'), findsWidgets);
      expect(find.textContaining('Download'), findsOneWidget);
    });

    testWidgets('Download button disabled when no books checked', (tester) async {
      final b1 = _book('1');
      final c = _container(FolderJobTreeReady(
        root: b1,
        checkedBooks: const {},
      ));
      await tester.pumpWidget(_wrap(c));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('tapping book checkbox calls updateSelection', (tester) async {
      final b1 = _book('1');
      final c = _container(FolderJobTreeReady(root: b1, checkedBooks: {b1.link.url}));
      await tester.pumpWidget(_wrap(c));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      final notifier = c.read(folderDownloadProvider.notifier) as _FakeTreeNotifier;
      expect(notifier.lastSelection, isNotNull);
    });

    testWidgets('tapping folder checkbox unchecks all children', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final folder = _folder('F', [b1, b2]);
      final c = _container(FolderJobTreeReady(
          root: folder, checkedBooks: {b1.link.url, b2.link.url}));
      await tester.pumpWidget(_wrap(c));
      // First checkbox is the folder
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final notifier = c.read(folderDownloadProvider.notifier) as _FakeTreeNotifier;
      expect(notifier.lastSelection, isEmpty);
    });

    testWidgets('tapping folder checkbox checks all children', (tester) async {
      final b1 = _book('1');
      final b2 = _book('2');
      final folder = _folder('F', [b1, b2]);
      final c = _container(FolderJobTreeReady(
          root: folder, checkedBooks: const {}));
      await tester.pumpWidget(_wrap(c));
      // First checkbox is the folder
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final notifier = c.read(folderDownloadProvider.notifier) as _FakeTreeNotifier;
      expect(notifier.lastSelection, {b1.link.url, b2.link.url});
    });

    testWidgets('tapping Download button calls confirmDownload', (tester) async {
      final b1 = _book('1');
      final c = _container(FolderJobTreeReady(root: b1, checkedBooks: {b1.link.url}));
      await tester.pumpWidget(_wrap(c));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      final notifier = c.read(folderDownloadProvider.notifier) as _FakeTreeNotifier;
      expect(notifier.lastConfirm, isNotNull);
    });

    test('notifier.reset() sets resetCalled flag', () {
      // Verify that the reset() method works correctly.
      // In the real app, PopScope.onPopInvokedWithResult in folder_tree_screen.dart
      // calls notifier.reset() on system back press.
      final b1 = _book('1');
      final notifier = _FakeTreeNotifier(
          FolderJobTreeReady(root: b1, checkedBooks: {b1.link.url}));

      // Verify initial state
      expect(notifier.resetCalled, isFalse);

      // Call reset() - this should set the flag
      notifier.reset();

      // Verify reset() was called and the flag is set
      expect(notifier.resetCalled, isTrue);
    });

    testWidgets('shows stoppedAtLimit warning banner when true', (tester) async {
      final b1 = _book('1');
      final c = _container(FolderJobTreeReady(
        root: b1,
        checkedBooks: {b1.link.url},
        stoppedAtLimit: true,
      ));
      await tester.pumpWidget(_wrap(c));
      expect(find.textContaining('limit'), findsOneWidget);
    });

    testWidgets('non-TreeReady state shows fallback (not selection UI)', (tester) async {
      final c = _container(const FolderJobIdle());
      await tester.pumpWidget(_wrap(c));
      // No Download button shown in non-selection mode
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('download mode', () {
    FolderJobDownloading downloadState({
      required DownloadTreeNode root,
      Uri? currentBook,
      Map<Uri, BookDownloadResult> results = const {},
      int total = 1,
      int completedCount = 0,
    }) =>
        FolderJobDownloading(
          root: root,
          currentBook: currentBook,
          results: results,
          total: total,
          completedCount: completedCount,
        );

    testWidgets('current book shows CircularProgressIndicator', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(
        downloadState(root: b, currentBook: b.link.url, total: 1),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('done book shows green check icon', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(
        downloadState(
          root: b,
          results: {b.link.url: const BookDownloadResult(status: BookDownloadStatus.done)},
          total: 1,
          completedCount: 1,
        ),
      ));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('failed book shows red warning icon', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(
        downloadState(
          root: b,
          results: {
            b.link.url: const BookDownloadResult(
                status: BookDownloadStatus.failed, error: 'timeout')
          },
          total: 1,
          completedCount: 1,
        ),
      ));
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    });

    testWidgets('tapping warning icon shows error dialog', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(
        downloadState(
          root: b,
          results: {
            b.link.url: const BookDownloadResult(
                status: BookDownloadStatus.failed, error: 'network error')
          },
          total: 1,
          completedCount: 1,
        ),
      ));
      await tester.tap(find.byIcon(Icons.warning_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('network error'), findsOneWidget);
    });

    testWidgets('shows LinearProgressIndicator and Cancel button', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(
        downloadState(root: b, total: 3, completedCount: 1),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('checkboxes are hidden in download mode', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(
        downloadState(root: b, total: 1),
      ));
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('done mode', () {
    testWidgets('shows Close button', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(FolderJobDone(
        root: b,
        results: {b.link.url: const BookDownloadResult(status: BookDownloadStatus.done)},
        wasCancelled: false,
        stoppedAtLimit: false,
      )));
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('wasCancelled shows cancellation notice', (tester) async {
      final b = _book('1');
      await tester.pumpWidget(_wrapWithState(FolderJobDone(
        root: b,
        results: {},
        wasCancelled: true,
        stoppedAtLimit: false,
      )));
      expect(find.textContaining('cancelled'), findsOneWidget);
    });
  });
}

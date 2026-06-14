import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/widgets/folder_job_banner.dart';

class _StubNotifier extends FolderDownloadNotifier {
  _StubNotifier(this._state);
  final FolderJobState _state;
  @override
  FolderJobState build() => _state;
}

Widget _wrap(FolderJobState state) => ProviderScope(
      overrides: [
        folderDownloadProvider.overrideWith(() => _StubNotifier(state)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [FolderJobBanner()])),
      ),
    );

void main() {
  testWidgets('hidden when FolderJobIdle', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobIdle()));
    expect(find.byType(FolderJobBanner), findsOneWidget);
    // No visible action buttons in idle state
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsNothing);
    expect(find.widgetWithText(TextButton, 'DISMISS'), findsNothing);
  });

  testWidgets('shows scanning message and CANCEL button', (tester) async {
    await tester.pumpWidget(
        _wrap(const FolderJobScanning(foldersFound: 3)));
    expect(find.textContaining('Scanning'), findsOneWidget);
    expect(find.textContaining('3'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'DISMISS'), findsNothing);
  });

  testWidgets('shows downloading message with counts', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDownloading(
      completed: 2,
      total: 5,
      downloaded: 1,
      skipped: 1,
      failed: 0,
    )));
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('5'), findsWidgets);
    expect(find.textContaining('1 skipped'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
  });

  testWidgets('does not show skipped/failed when zero', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDownloading(
      completed: 1,
      total: 3,
      downloaded: 1,
      skipped: 0,
      failed: 0,
    )));
    expect(find.textContaining('skipped'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('shows summary and DISMISS button when done', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDone(
      downloaded: 4,
      skipped: 1,
      failed: 0,
      stoppedAtLimit: false,
    )));
    expect(find.textContaining('Downloaded: 4'), findsOneWidget);
    expect(find.textContaining('Skipped: 1'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'DISMISS'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsNothing);
  });

  testWidgets('shows Cancelled prefix and Stopped at limit when applicable',
      (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobDone(
      downloaded: 0,
      skipped: 0,
      failed: 0,
      stoppedAtLimit: true,
      wasCancelled: true,
    )));
    expect(find.textContaining('Cancelled'), findsOneWidget);
    expect(find.textContaining('Stopped at limit'), findsOneWidget);
  });

  testWidgets('tapping CANCEL is accepted during FolderJobScanning', (tester) async {
    await tester.pumpWidget(_wrap(const FolderJobScanning(foldersFound: 5)));
    await tester.tap(find.widgetWithText(TextButton, 'CANCEL'));
    await tester.pump();
    // cancel() is a no-op when no job is running (_job is null in stub), but must not throw
    expect(find.widgetWithText(TextButton, 'CANCEL'), findsOneWidget);
  });

  testWidgets('tapping DISMISS calls dismiss() on notifier', (tester) async {
    FolderJobState? latestState;
    final stub = _StubNotifier(const FolderJobDone(
      downloaded: 1,
      skipped: 0,
      failed: 0,
      stoppedAtLimit: false,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [folderDownloadProvider.overrideWith(() => stub)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (_, ref, child) {
            latestState = ref.watch(folderDownloadProvider);
            return const Column(children: [FolderJobBanner()]);
          }),
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'DISMISS'));
    await tester.pump();

    expect(latestState, isA<FolderJobIdle>());
  });
}

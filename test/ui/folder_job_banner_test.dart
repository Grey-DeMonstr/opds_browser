import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/ui/widgets/folder_job_banner.dart';

// Banner is a temporary stub (deleted in Task 9) — just verify it renders.
void main() {
  testWidgets('FolderJobBanner renders without error (stub)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FolderJobBanner()),
      ),
    );
    expect(find.byType(FolderJobBanner), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });
}

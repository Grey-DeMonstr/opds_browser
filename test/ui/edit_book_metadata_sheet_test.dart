import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/ui/widgets/edit_book_metadata_sheet.dart';

LibraryBook _book() => LibraryBook(
  relativePath: 'Jane Doe/One.fb2',
  documentUri: 'content://doc/1',
  parentUri: 'content://dir/1',
  meta: const LocalBookMetadata(title: 'One', author: 'Jane Doe'),
);

void main() {
  testWidgets('sheet reserves room for the system navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: EditBookMetadataSheet(book: _book())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final padding = tester
        .widget<Padding>(
          find
              .descendant(
                of: find.byType(EditBookMetadataSheet),
                matching: find.byType(Padding),
              )
              .first,
        )
        .padding
        .resolve(TextDirection.ltr);
    // 24 of its own bottom padding plus the 48px navigation bar inset.
    expect(padding.bottom, 24 + 48);
  });
}

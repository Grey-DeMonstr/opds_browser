import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/ui/local_library_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _StubLibraryNotifier extends LocalLibraryNotifier {
  _StubLibraryNotifier(this.initial);
  final LocalLibraryState initial;

  @override
  LocalLibraryState build() => initial;
}

LibraryBook _book(String title) => LibraryBook(
  relativePath: 'Jane Doe/$title.fb2',
  documentUri: 'content://doc/$title',
  parentUri: 'content://dir/1',
  meta: LocalBookMetadata(title: title, author: 'Jane Doe'),
);

Widget _buildApp(LocalLibraryState state) => ProviderScope(
  overrides: [
    localLibraryNotifierProvider.overrideWith(
      () => _StubLibraryNotifier(state),
    ),
  ],
  child: const MaterialApp(home: LocalLibraryScreen()),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('book tree is inset above the system navigation bar', (
    tester,
  ) async {
    final state = LibraryReady(
      root: LibraryFolder(
        name: '',
        children: [
          LibraryFolder(
            name: 'Jane Doe',
            children: [_book('One'), _book('Two')],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: _buildApp(state),
      ),
    );
    await tester.pumpAndSettle();

    final listBottom = tester.getRect(find.byType(ListView)).bottom;
    expect(listBottom, lessThanOrEqualTo(600 - 48));
  });
}

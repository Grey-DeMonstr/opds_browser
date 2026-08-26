import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/browse_screen.dart';
import 'package:opds_browser/ui/download_result_snack_bar.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeFeedRepository implements FeedRepository {
  @override
  Future<CachedFeed> getFeed(
    int catalogId,
    Uri url, {
    bool forceRefresh = false,
  }) async => CachedFeed(
    feed: const ParsedFeed(title: 'Feed', entries: []),
    fetchedAt: DateTime(2026),
    fromCache: false,
  );
}

class _FakeFavoritesRepository implements FavoritesRepository {
  @override
  Future<List<Favorite>> getAll() async => const [];
  @override
  Future<void> add(int catalogId, Uri url, String title) async {}
  @override
  Future<void> remove(int favoriteId) async {}
  @override
  Future<bool> isFavorite(int catalogId, Uri url) async => false;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(target: CustomSafFolder('/library', 'Library'));
}

class _RecordingFileOpener implements FileOpener {
  final opened = <(String, String)>[];
  Object? failure;

  @override
  Future<void> open(String uri, String mimeType) async {
    opened.add((uri, mimeType));
    if (failure != null) throw failure!;
  }
}

// ── Harness ──────────────────────────────────────────────────────────────────

const _done = DownloadDone(
  contentUri: '/library/book.fb2',
  fileName: 'book.fb2',
  alreadyExisted: false,
  mimeType: 'application/x-fictionbook+xml',
);

void main() {
  late _RecordingFileOpener opener;

  setUp(() => opener = _RecordingFileOpener());

  /// Builds the app with [depth] browse screens stacked on the navigator, the
  /// way a reader gets to a book: catalogue root, folder, sub-folder.
  Future<ProviderContainer> pumpStack(WidgetTester tester, int depth) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              BrowseScreen(catalogId: 1, url: Uri.parse('https://e/root')),
        ),
        GoRoute(
          path: '/browse',
          builder: (_, state) => BrowseScreen(
            catalogId: 1,
            url: Uri.parse('https://e/${state.uri.queryParameters['n']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(_FakeFeedRepository()),
          favoritesRepositoryProvider.overrideWithValue(
            _FakeFavoritesRepository(),
          ),
          settingsProvider.overrideWith(_FakeSettingsNotifier.new),
          fileOpenerProvider.overrideWithValue(opener),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          builder: (context, child) =>
              DownloadResultSnackBar(child: child ?? const SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i < depth; i++) {
      router.push('/browse?n=$i');
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
    );
  }

  Future<void> report(
    WidgetTester tester,
    ProviderContainer container, {
    DownloadDone result = _done,
  }) async {
    container.read(lastDownloadResultProvider.notifier).set(result);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('announces a finished download once', (tester) async {
    final container = await pumpStack(tester, 1);
    await report(tester, container);

    expect(find.text('Downloaded: book.fb2'), findsOneWidget);
  });

  testWidgets('announces it only once however deep the browse stack is', (
    tester,
  ) async {
    final container = await pumpStack(tester, 3);
    await report(tester, container);

    expect(find.text('Downloaded: book.fb2'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Downloaded: book.fb2'), findsNothing);
  });

  testWidgets('Open hands the downloaded file to the platform', (tester) async {
    final container = await pumpStack(tester, 2);
    await report(tester, container);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(opener.opened, hasLength(1));
    expect(opener.opened.single.$1, '/library/book.fb2');
    expect(opener.opened.single.$2, 'application/x-fictionbook+xml');
  });

  testWidgets('says so when the file cannot be opened', (tester) async {
    opener.failure = Exception('no handler');
    final container = await pumpStack(tester, 1);
    await report(tester, container);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open book.fb2'), findsOneWidget);
  });

  testWidgets('offers no Open for a book that was already there', (
    tester,
  ) async {
    final container = await pumpStack(tester, 1);
    await report(
      tester,
      container,
      result: const DownloadDone(
        contentUri: '',
        fileName: 'book.fb2',
        alreadyExisted: true,
        mimeType: 'application/x-fictionbook+xml',
      ),
    );

    expect(find.text('Already downloaded: book.fb2'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });
}

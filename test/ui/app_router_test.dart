import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/app.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class _FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<Catalog>> getAll() async => [];

  @override
  Future<Catalog> add(String title, Uri rootUrl) async =>
      throw UnimplementedError();

  @override
  Future<void> update(Catalog catalog) async {}

  @override
  Future<void> delete(int catalogId) async {}
}

class _FakeFavoritesRepository implements FavoritesRepository {
  @override
  Future<List<Favorite>> getAll() async => [];

  @override
  Future<void> add(int catalogId, Uri url, String title) async {}

  @override
  Future<void> remove(int favoriteId) async {}

  @override
  Future<bool> isFavorite(int catalogId, Uri url) async => false;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings initialSettings;

  _FakeSettingsNotifier({AppSettings? settings})
    : initialSettings = settings ?? const AppSettings();

  @override
  Future<AppSettings> build() async => initialSettings;
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
    'router redirect: when target is null, navigating to / redirects to /setup',
    (tester) async {
      // Use AppSettings() with no target (target = null)
      final notifier = _FakeSettingsNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWithValue(
              _FakeCatalogRepository(),
            ),
            favoritesRepositoryProvider.overrideWithValue(
              _FakeFavoritesRepository(),
            ),
            settingsProvider.overrideWith(() => notifier),
          ],
          child: const OpdsBrowserApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Should be on setup screen since target is null
      expect(find.text('Pick library folder'), findsOneWidget);
    },
  );

  testWidgets(
    'router redirect: when target is set, navigating to /setup redirects to /',
    (tester) async {
      // Use AppSettings with a target folder
      final notifier = _FakeSettingsNotifier(
        settings: const AppSettings(
          target: CustomSafFolder('content://example', 'Folder'),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWithValue(
              _FakeCatalogRepository(),
            ),
            favoritesRepositoryProvider.overrideWithValue(
              _FakeFavoritesRepository(),
            ),
            settingsProvider.overrideWith(() => notifier),
          ],
          child: const OpdsBrowserApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Should be on start screen (home) since target is set
      expect(find.text('OPDS Browser'), findsOneWidget);
    },
  );
}

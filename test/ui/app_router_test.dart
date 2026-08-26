import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/app.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';

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
    'with no library folder the app still opens on the start screen',
    (tester) async {
      // The folder is asked for on demand now, not behind a first-launch gate.
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

      expect(find.text('OPDS Browser'), findsOneWidget);
      expect(find.text('Pick library folder'), findsNothing);
    },
  );

  testWidgets('app themes: dark is Nocturne, light stays Material', (
    tester,
  ) async {
    final notifier = _FakeSettingsNotifier(
      settings: const AppSettings(
        target: CustomSafFolder('content://example', 'Folder'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(_FakeCatalogRepository()),
          favoritesRepositoryProvider.overrideWithValue(
            _FakeFavoritesRepository(),
          ),
          settingsProvider.overrideWith(() => notifier),
        ],
        child: const OpdsBrowserApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme?.colorScheme.surface, const Color(0xFF161826));
    expect(app.theme?.brightness, Brightness.light);
    expect(app.darkTheme?.extension<AppPalette>(), isNotNull);
    expect(app.theme?.extension<AppPalette>(), isNotNull);
  });
}

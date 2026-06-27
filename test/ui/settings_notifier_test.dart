import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';
import 'package:opds_browser/ui/providers.dart';

class FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings;
  FakeSettingsRepository(this._settings);

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

ProviderContainer _makeContainer({
  required AppSettings initial,
  bool permissionGranted = true,
}) {
  return ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        FakeSettingsRepository(initial),
      ),
      safPermissionCheckerProvider.overrideWithValue(
        (_) async => permissionGranted,
      ),
    ],
  );
}

void main() {
  test('build() loads settings from repository', () async {
    final c = _makeContainer(
      initial: const AppSettings(target: SystemDownloads()),
    );
    addTearDown(c.dispose);

    final settings = await c.read(settingsProvider.future);
    expect(settings.target, isA<SystemDownloads>());
    expect(settings.createAuthorFolder, isFalse);
  });

  test(
    'build() reverts to SystemDownloads when permission is revoked',
    () async {
      const uri = 'content://example/tree/primary';
      final c = _makeContainer(
        initial: const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
        permissionGranted: false,
      );
      addTearDown(c.dispose);

      final settings = await c.read(settingsProvider.future);
      expect(settings.target, isA<SystemDownloads>());
      expect(c.read(settingsProvider.notifier).permissionRevoked, isTrue);
    },
  );

  test('build() keeps CustomSafFolder when permission is granted', () async {
    const uri = 'content://example/tree/primary';
    final c = _makeContainer(
      initial: const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      permissionGranted: true,
    );
    addTearDown(c.dispose);

    final settings = await c.read(settingsProvider.future);
    expect(settings.target, isA<CustomSafFolder>());
    expect(c.read(settingsProvider.notifier).permissionRevoked, isFalse);
  });

  test('setSystemDownloads() updates state and persists', () async {
    const uri = 'content://example/tree/primary';
    final repo = FakeSettingsRepository(
      const AppSettings(target: CustomSafFolder(uri, 'D')),
    );
    final c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        safPermissionCheckerProvider.overrideWithValue((_) async => true),
      ],
    );
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setSystemDownloads();

    expect(c.read(settingsProvider).value?.target, isA<SystemDownloads>());
    expect((await repo.load()).target, isA<SystemDownloads>());
  });

  test('setCreateAuthorFolder(true) updates state and persists', () async {
    final repo = FakeSettingsRepository(
      const AppSettings(target: SystemDownloads()),
    );
    final c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        safPermissionCheckerProvider.overrideWithValue((_) async => true),
      ],
    );
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setCreateAuthorFolder(true);

    expect(c.read(settingsProvider).value?.createAuthorFolder, isTrue);
    expect((await repo.load()).createAuthorFolder, isTrue);
  });

  test('setCreateSeriesFolder(true) updates state and persists', () async {
    final repo = FakeSettingsRepository(
      const AppSettings(target: SystemDownloads()),
    );
    final c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        safPermissionCheckerProvider.overrideWithValue((_) async => true),
      ],
    );
    addTearDown(c.dispose);

    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setCreateSeriesFolder(true);

    expect(c.read(settingsProvider).value?.createSeriesFolder, isTrue);
    expect((await repo.load()).createSeriesFolder, isTrue);
  });
}

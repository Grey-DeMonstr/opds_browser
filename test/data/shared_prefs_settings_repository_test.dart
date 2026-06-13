import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SharedPrefsSettingsRepository', () {
    test('load returns defaults when no keys are set', () async {
      final repo = SharedPrefsSettingsRepository();
      final settings = await repo.load();
      expect(settings.target, isA<SystemDownloads>());
      expect(settings.createAuthorFolder, isFalse);
      expect(settings.createSeriesFolder, isFalse);
    });

    test('save and load roundtrip SystemDownloads', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(target: SystemDownloads()));
      final loaded = await repo.load();
      expect(loaded.target, isA<SystemDownloads>());
    });

    test('save and load roundtrip CustomSafFolder — uri and displayName',
        () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      );
      final loaded = await repo.load();
      expect(loaded.target, isA<CustomSafFolder>());
      expect((loaded.target as CustomSafFolder).uriString, uri);
      expect((loaded.target as CustomSafFolder).displayName, 'Downloads');
    });

    test('switching from custom back to system clears stored URI and displayName',
        () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(target: CustomSafFolder(uri, 'Folder')),
      );
      await repo.save(const AppSettings(target: SystemDownloads()));
      final loaded = await repo.load();
      expect(loaded.target, isA<SystemDownloads>());
    });

    test('createAuthorFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
      ));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isFalse);
    });

    test('createSeriesFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(
        target: SystemDownloads(),
        createSeriesFolder: true,
      ));
      final loaded = await repo.load();
      expect(loaded.createSeriesFolder, isTrue);
      expect(loaded.createAuthorFolder, isFalse);
    });

    test('both folder flags persist when both are true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(
        target: SystemDownloads(),
        createAuthorFolder: true,
        createSeriesFolder: true,
      ));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opds_browser/data/shared_prefs_settings_repository.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SharedPrefsSettingsRepository', () {
    test('load returns null target when no keys are set', () async {
      final repo = SharedPrefsSettingsRepository();
      final settings = await repo.load();
      expect(settings.target, isNull);
    });

    test('folder flags default to true on a fresh install', () async {
      final repo = SharedPrefsSettingsRepository();
      final settings = await repo.load();
      expect(settings.createAuthorFolder, isTrue);
      expect(settings.createSeriesFolder, isTrue);
    });

    test('folder flags stay off once they are turned off', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings());
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isFalse);
      expect(loaded.createSeriesFolder, isFalse);
    });

    test('save and load roundtrip null target', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings());
      final loaded = await repo.load();
      expect(loaded.target, isNull);
    });

    test('save and load roundtrip CustomSafFolder', () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(target: CustomSafFolder(uri, 'Downloads')),
      );
      final loaded = await repo.load();
      expect(loaded.target?.uriString, uri);
      expect(loaded.target?.displayName, 'Downloads');
    });

    test('switching from custom to null clears stored URI', () async {
      const uri = 'content://com.android.externalstorage/tree/primary';
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(target: CustomSafFolder(uri, 'Folder')),
      );
      await repo.save(const AppSettings());
      final loaded = await repo.load();
      expect(loaded.target, isNull);
    });

    test('createAuthorFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(createAuthorFolder: true));
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isFalse);
    });

    test('createSeriesFolder persists as true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(createSeriesFolder: true));
      final loaded = await repo.load();
      expect(loaded.createSeriesFolder, isTrue);
      expect(loaded.createAuthorFolder, isFalse);
    });

    test('debugMode defaults to false when never saved', () async {
      final repo = SharedPrefsSettingsRepository();
      expect((await repo.load()).debugMode, isFalse);
    });

    test('debugMode survives a save/load roundtrip', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(debugMode: true));
      expect((await repo.load()).debugMode, isTrue);
    });

    test('debugMode can be turned back off', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(const AppSettings(debugMode: true));
      await repo.save(const AppSettings());
      expect((await repo.load()).debugMode, isFalse);
    });

    test('both folder flags persist when both are true', () async {
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const AppSettings(createAuthorFolder: true, createSeriesFolder: true),
      );
      final loaded = await repo.load();
      expect(loaded.createAuthorFolder, isTrue);
      expect(loaded.createSeriesFolder, isTrue);
    });
  });
}

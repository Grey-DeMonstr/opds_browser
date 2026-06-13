import 'package:shared_preferences/shared_preferences.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/repositories.dart';

class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _keyKind = 'download_target_kind';
  static const _keyUri = 'download_target_uri';
  static const _keyDisplayName = 'download_target_display_name';
  static const _keyAuthor = 'folder_per_author';
  static const _keySeries = 'folder_per_series';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kind = prefs.getString(_keyKind) ?? 'system';
    final uri = prefs.getString(_keyUri);
    final displayName = prefs.getString(_keyDisplayName) ?? '';
    final target = (kind == 'custom' && uri != null)
        ? CustomSafFolder(uri, displayName)
        : const SystemDownloads();
    return AppSettings(
      target: target,
      createAuthorFolder: prefs.getBool(_keyAuthor) ?? false,
      createSeriesFolder: prefs.getBool(_keySeries) ?? false,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final target = settings.target;
    if (target is CustomSafFolder) {
      await prefs.setString(_keyKind, 'custom');
      await prefs.setString(_keyUri, target.uriString);
      await prefs.setString(_keyDisplayName, target.displayName);
    } else {
      await prefs.setString(_keyKind, 'system');
      await prefs.remove(_keyUri);
      await prefs.remove(_keyDisplayName);
    }
    await prefs.setBool(_keyAuthor, settings.createAuthorFolder);
    await prefs.setBool(_keySeries, settings.createSeriesFolder);
  }
}

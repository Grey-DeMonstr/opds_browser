import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/settings_screen.dart';

// ── Fake notifier ────────────────────────────────────────────────────────────

class FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  final bool _triggerPermissionRevoked;
  FakeSettingsNotifier({
    required this._initial,
    this._triggerPermissionRevoked = false,
  });

  @override
  Future<AppSettings> build() async {
    if (_triggerPermissionRevoked) {
      permissionRevoked = true;
      return const AppSettings();
    }
    return _initial;
  }

  @override
  Future<bool> pickCustomFolder() async {
    final newSettings = (state.value ?? const AppSettings()).copyWith(
      target: const CustomSafFolder('content://fake/tree', 'TestFolder'),
    );
    state = AsyncData(newSettings);
    return true;
  }

  @override
  Future<void> setCreateAuthorFolder(bool value) async {
    state = AsyncData(
      (state.value ?? const AppSettings()).copyWith(createAuthorFolder: value),
    );
  }

  @override
  Future<void> setCreateSeriesFolder(bool value) async {
    state = AsyncData(
      (state.value ?? const AppSettings()).copyWith(createSeriesFolder: value),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

Widget buildApp(FakeSettingsNotifier notifier) {
  return ProviderScope(
    overrides: [settingsProvider.overrideWith(() => notifier)],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('buildPathExample', () {
    test('no folders: filename directly under Downloads', () {
      const s = AppSettings();
      expect(
        buildPathExample(s),
        'Downloads/Jane Doe - Great Series #1 - Book Title.fb2',
      );
    });

    test('author folder enabled — author omitted from filename', () {
      const s = AppSettings(createAuthorFolder: true);
      expect(
        buildPathExample(s),
        'Downloads/Jane Doe/Great Series #1 - Book Title.fb2',
      );
    });

    test('series folder enabled — series omitted from filename', () {
      const s = AppSettings(createSeriesFolder: true);
      expect(
        buildPathExample(s),
        'Downloads/Great Series/Jane Doe - Book Title.fb2',
      );
    });

    test('both folders enabled — author and series omitted from filename', () {
      const s = AppSettings(createAuthorFolder: true, createSeriesFolder: true);
      expect(
        buildPathExample(s),
        'Downloads/Jane Doe/Great Series/Book Title.fb2',
      );
    });
  });

  group('SettingsScreen', () {
    testWidgets('shows no-folder subtitle when target is null', (tester) async {
      await tester.pumpWidget(
        buildApp(FakeSettingsNotifier(initial: const AppSettings())),
      );
      await tester.pumpAndSettle();
      expect(find.text('No folder selected'), findsOneWidget);
      expect(find.text('Change…'), findsOneWidget);
    });

    testWidgets('shows display name when CustomSafFolder is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          FakeSettingsNotifier(
            initial: const AppSettings(
              target: CustomSafFolder('content://x', 'My Folder'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected: My Folder'), findsOneWidget);
    });

    testWidgets('tapping Change calls pickCustomFolder and updates subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(FakeSettingsNotifier(initial: const AppSettings())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change…'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: TestFolder'), findsOneWidget);
    });

    testWidgets('author checkbox toggles', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();
      expect(notifier.state.value?.createAuthorFolder, isTrue);
    });

    testWidgets('series checkbox toggles', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a folder per series'));
      await tester.pumpAndSettle();
      expect(notifier.state.value?.createSeriesFolder, isTrue);
    });

    testWidgets('path caption updates live when author checkbox changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(FakeSettingsNotifier(initial: const AppSettings())),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Downloads/Jane Doe - Great Series #1 - Book Title.fb2'),
        findsOneWidget,
      );
      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();
      expect(
        find.text('Downloads/Jane Doe/Great Series #1 - Book Title.fb2'),
        findsOneWidget,
      );
    });

    testWidgets('permission-revoked snackbar appears on startup', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          FakeSettingsNotifier(
            initial: const AppSettings(),
            triggerPermissionRevoked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Custom downloads folder is no longer accessible — please select a new folder.',
        ),
        findsOneWidget,
      );
    });
  });
}

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
  Future<void> clearTarget() async {
    state = AsyncData(
      (state.value ?? const AppSettings()).copyWith(clearTarget: true),
    );
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
    testWidgets(
      'renders both radios with System Downloads selected by default',
      (tester) async {
        final notifier = FakeSettingsNotifier(initial: const AppSettings());
        await tester.pumpWidget(buildApp(notifier));
        await tester.pumpAndSettle();

        expect(find.text('System Downloads folder'), findsOneWidget);
        expect(find.text('Custom folder…'), findsOneWidget);
        expect(find.text('Tap to select a folder'), findsOneWidget);
      },
    );

    testWidgets('shows display name subtitle when CustomSafFolder is set', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(
          target: CustomSafFolder('content://x', 'My Folder'),
        ),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      expect(find.text('Selected: My Folder'), findsOneWidget);
    });

    testWidgets(
      'tapping Custom folder tile calls pickCustomFolder and updates subtitle',
      (tester) async {
        final notifier = FakeSettingsNotifier(initial: const AppSettings());
        await tester.pumpWidget(buildApp(notifier));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Custom folder…'));
        await tester.pumpAndSettle();

        expect(find.text('Selected: TestFolder'), findsOneWidget);
      },
    );

    testWidgets('tapping System Downloads radio calls clearTarget', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(
          target: CustomSafFolder('content://x', 'My Folder'),
        ),
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('System Downloads folder'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to select a folder'), findsOneWidget);
    });

    testWidgets('author checkbox toggles on and off', (tester) async {
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create a folder per author'));
      await tester.pumpAndSettle();

      expect(notifier.state.value?.createAuthorFolder, isTrue);
    });

    testWidgets('series checkbox toggles on and off', (tester) async {
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
      final notifier = FakeSettingsNotifier(initial: const AppSettings());
      await tester.pumpWidget(buildApp(notifier));
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
      final notifier = FakeSettingsNotifier(
        initial: const AppSettings(),
        triggerPermissionRevoked: true,
      );
      await tester.pumpWidget(buildApp(notifier));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Custom downloads folder is no longer accessible — reverted to system Downloads.',
        ),
        findsOneWidget,
      );
    });
  });
}

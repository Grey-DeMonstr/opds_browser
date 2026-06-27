import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/setup_screen.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  bool pickCalled = false;

  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<bool> pickCustomFolder() async {
    pickCalled = true;
    state = AsyncData(
      const AppSettings(target: CustomSafFolder('content://fake', 'Lib')),
    );
    return true;
  }
}

void main() {
  testWidgets('SetupScreen shows Pick library folder button', (tester) async {
    final notifier = _FakeSettingsNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(() => notifier)],
        child: const MaterialApp(home: SetupScreen()),
      ),
    );
    expect(find.text('Pick library folder'), findsOneWidget);
    expect(
      find.text('Pick a folder where your books are stored'),
      findsOneWidget,
    );
  });

  testWidgets('tapping Pick calls pickCustomFolder', (tester) async {
    final notifier = _FakeSettingsNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(() => notifier)],
        child: const MaterialApp(home: SetupScreen()),
      ),
    );
    await tester.tap(find.text('Pick library folder'));
    await tester.pumpAndSettle();
    expect(notifier.pickCalled, isTrue);
  });
}

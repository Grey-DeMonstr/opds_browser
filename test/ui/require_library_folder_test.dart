import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/require_library_folder.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier({
    this.initial = const AppSettings(),
    this.pickSucceeds = true,
  });

  final AppSettings initial;
  final bool pickSucceeds;
  int pickCalls = 0;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<bool> pickCustomFolder() async {
    pickCalls++;
    if (!pickSucceeds) return false;
    state = AsyncData(
      const AppSettings(target: CustomSafFolder('content://fake', 'Lib')),
    );
    return true;
  }
}

/// Carries the gate's answer out of the button callback.
class _Answer {
  bool? value;
}

/// Pumps a button that runs the gate, then taps it. Any dialog the gate
/// raises is left on screen for the test to act on.
Future<_Answer> _tapGate(WidgetTester tester, SettingsNotifier notifier) async {
  final answer = _Answer();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                answer.value = await ensureLibraryFolder(context, ref);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  testWidgets('returns true without asking when a folder is already set', (
    tester,
  ) async {
    final notifier = _FakeSettingsNotifier(
      initial: const AppSettings(
        target: CustomSafFolder('content://example', 'Folder'),
      ),
    );

    final answer = await _tapGate(tester, notifier);

    expect(answer.value, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(notifier.pickCalls, 0);
  });

  testWidgets('asks before picking when no folder is set', (tester) async {
    final notifier = _FakeSettingsNotifier();

    await _tapGate(tester, notifier);

    expect(find.text('Choose a library folder'), findsOneWidget);
    expect(notifier.pickCalls, 0);
  });

  testWidgets('Choose folder picks a folder and returns true', (tester) async {
    final notifier = _FakeSettingsNotifier();

    final answer = await _tapGate(tester, notifier);
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();

    expect(notifier.pickCalls, 1);
    expect(answer.value, isTrue);
  });

  testWidgets('Choose folder returns false when the picker is dismissed', (
    tester,
  ) async {
    final notifier = _FakeSettingsNotifier(pickSucceeds: false);

    final answer = await _tapGate(tester, notifier);
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();

    expect(notifier.pickCalls, 1);
    expect(answer.value, isFalse);
  });

  testWidgets('Cancel returns false and never opens the picker', (
    tester,
  ) async {
    final notifier = _FakeSettingsNotifier();

    final answer = await _tapGate(tester, notifier);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(notifier.pickCalls, 0);
    expect(answer.value, isFalse);
  });
}

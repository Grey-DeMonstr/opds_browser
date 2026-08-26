import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/ui/providers.dart';

/// Makes sure a library folder is configured before an action that needs one.
///
/// Returns true when a folder is available — already chosen, or picked just
/// now. The app asks here, on demand, rather than at first launch, so the
/// folder is only requested once it is actually about to be used.
Future<bool> ensureLibraryFolder(BuildContext context, WidgetRef ref) async {
  // Awaits the future rather than reading `.value`: on a cold start the
  // notifier may still be loading, and a null there is indistinguishable from
  // a genuinely unset folder.
  final settings = await ref.read(settingsProvider.future);
  if (settings.target != null) return true;
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose a library folder'),
      content: const Text(
        'OPDS Browser needs a folder on your device to store downloaded '
        'books and read your local library.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Choose folder'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  return ref.read(settingsProvider.notifier).pickCustomFolder();
}

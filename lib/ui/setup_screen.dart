import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/ui/providers.dart';

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Pick a folder where your books are stored',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Pick library folder'),
                onPressed: () =>
                    ref.read(settingsProvider.notifier).pickCustomFolder(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

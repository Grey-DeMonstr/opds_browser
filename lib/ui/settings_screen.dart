import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/providers.dart';

String buildPathExample(AppSettings settings) {
  const author = 'Jane Doe';
  const series = 'Great Series';
  final folders = <String>['Downloads'];
  if (settings.createAuthorFolder) folders.add(author);
  if (settings.createSeriesFolder) folders.add(series);
  final fileParts = <String>[];
  if (!settings.createAuthorFolder) fileParts.add(author);
  if (!settings.createSeriesFolder) fileParts.add('$series #1');
  fileParts.add('Book Title');
  return '${folders.join('/')}/${fileParts.join(' - ')}.fb2';
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final ProviderSubscription<AsyncValue<AppSettings>> _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(settingsProvider, (_, next) {
      if (next is AsyncData) {
        final notifier = ref.read(settingsProvider.notifier);
        if (notifier.permissionRevoked) {
          notifier.permissionRevoked = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Custom downloads folder is no longer accessible'
                  ' — reverted to system Downloads.',
                ),
              ),
            );
          });
        }
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => _SettingsBody(settings: settings),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final AppSettings settings;
  const _SettingsBody({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);
    final isCustom = settings.target is CustomSafFolder;

    return ListView(
      children: [
        const ListTile(title: Text('Downloads folder')),
        if (Platform.isAndroid) ...[
          ListTile(
            title: const Text('Custom folder…'),
            subtitle: isCustom
                ? Text(
                    'Selected: ${(settings.target as CustomSafFolder).displayName}',
                  )
                : const Text('Tap to select a folder'),
            onTap: () => notifier.pickCustomFolder(),
          ),
        ] else ...[
          RadioGroup<bool>(
            groupValue: isCustom,
            onChanged: (value) {
              if (value == true) {
                notifier.pickCustomFolder();
              } else {
                notifier.setSystemDownloads();
              }
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  title: const Text('System Downloads folder'),
                  value: false,
                ),
                ListTile(
                  leading: const Radio<bool>(value: true),
                  title: const Text('Custom folder…'),
                  subtitle: isCustom
                      ? Text(
                          'Selected: ${(settings.target as CustomSafFolder).displayName}',
                        )
                      : const Text('Tap to select a folder'),
                  onTap: () => notifier.pickCustomFolder(),
                ),
              ],
            ),
          ),
        ],
        const Divider(),
        const ListTile(title: Text('File organization')),
        CheckboxListTile(
          title: const Text('Create a folder per author'),
          value: settings.createAuthorFolder,
          onChanged: (v) => notifier.setCreateAuthorFolder(v ?? false),
        ),
        CheckboxListTile(
          title: const Text('Create a folder per series'),
          value: settings.createSeriesFolder,
          onChanged: (v) => notifier.setCreateSeriesFolder(v ?? false),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            buildPathExample(settings),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

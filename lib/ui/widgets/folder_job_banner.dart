import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';

class FolderJobBanner extends ConsumerWidget {
  const FolderJobBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(folderDownloadProvider);
    if (state is FolderJobIdle) return const SizedBox.shrink();

    final notifier = ref.read(folderDownloadProvider.notifier);

    final String message;
    final Widget trailing;

    switch (state) {
      case FolderJobIdle():
        return const SizedBox.shrink();

      case FolderJobScanning(:final foldersFound):
        message = 'Scanning folders… ($foldersFound found)';
        trailing = TextButton(
          onPressed: notifier.cancel,
          child: const Text('CANCEL'),
        );

      case FolderJobDownloading(
          :final completed,
          :final total,
          :final skipped,
          :final failed,
        ):
        final extras = [
          if (skipped > 0) '$skipped skipped',
          if (failed > 0) '$failed failed',
        ];
        message = 'Downloading $completed of $total'
            '${extras.isNotEmpty ? ' · ${extras.join(' · ')}' : ''}';
        trailing = TextButton(
          onPressed: notifier.cancel,
          child: const Text('CANCEL'),
        );

      case FolderJobDone(
          :final downloaded,
          :final skipped,
          :final failed,
          :final stoppedAtLimit,
          :final wasCancelled,
        ):
        final parts = <String>[
          if (wasCancelled) 'Cancelled.',
          'Downloaded: $downloaded · Skipped: $skipped · Failed: $failed',
          if (stoppedAtLimit) 'Stopped at limit',
        ];
        message = parts.join(' ');
        trailing = TextButton(
          onPressed: notifier.dismiss,
          child: const Text('DISMISS'),
        );
    }

    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

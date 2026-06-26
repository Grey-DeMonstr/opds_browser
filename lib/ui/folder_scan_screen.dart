import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';

class FolderScanScreen extends ConsumerStatefulWidget {
  const FolderScanScreen({
    required this.catalogId,
    required this.url,
    super.key,
  });
  final int catalogId;
  final String url;

  @override
  ConsumerState<FolderScanScreen> createState() => _FolderScanScreenState();
}

class _FolderScanScreenState extends ConsumerState<FolderScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(folderDownloadProvider.notifier)
          .start(widget.catalogId, Uri.parse(widget.url));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<FolderJobState>(folderDownloadProvider, (_, next) {
      if (!mounted) return;
      if (next is FolderJobTreeReady) {
        context.replace('/folder-tree');
      } else if (next is FolderJobDone) {
        context.pop();
      }
    });

    final state = ref.watch(folderDownloadProvider);
    final foldersFound = state is FolderJobScanning ? state.foldersFound : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ref.read(folderDownloadProvider.notifier).cancel();
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Scanning folder')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text('Scanning… ($foldersFound folders found)'),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  ref.read(folderDownloadProvider.notifier).cancel();
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

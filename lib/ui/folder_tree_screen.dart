import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';

class FolderTreeScreen extends ConsumerWidget {
  const FolderTreeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(folderDownloadProvider);
    return switch (state) {
      FolderJobTreeReady() => _SelectionView(state: state),
      FolderJobDownloading() => _DownloadView(state: state),
      FolderJobDone() => _DoneView(state: state),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

// ── Selection view ─────────────────────────────────────────────────────────────

class _SelectionView extends ConsumerWidget {
  const _SelectionView({required this.state});
  final FolderJobTreeReady state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(folderDownloadProvider.notifier);

    // Pop the screen when state leaves FolderJobTreeReady (cancelled or reset
    // externally).
    ref.listen<FolderJobState>(folderDownloadProvider, (previous, next) {
      if (next is! FolderJobTreeReady && context.mounted) {
        context.pop();
      }
    });

    final rows = _flattenTree(state.root, 0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          notifier.reset();
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Select books')),
        body: Column(
          children: [
            if (state.stoppedAtLimit)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Large catalogue — some content may not be shown'
                  ' (size limit reached).',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final (node, depth) = rows[i];
                  return _TreeRow(
                    node: node,
                    depth: depth,
                    checkedBooks: state.checkedBooks,
                    onChanged: notifier.updateSelection,
                    subtreeBooks: _collectBookUrls(node),
                  );
                },
              ),
            ),
            _SelectionBottomBar(
              checkedBooks: state.checkedBooks,
              notifier: notifier,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tree row ───────────────────────────────────────────────────────────────────

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.checkedBooks,
    required this.onChanged,
    required this.subtreeBooks,
  });

  final DownloadTreeNode node;
  final int depth;
  final Set<Uri> checkedBooks;
  final void Function(Set<Uri>) onChanged;
  final Set<Uri> subtreeBooks;

  @override
  Widget build(BuildContext context) {
    final indent = depth * 16.0;
    return switch (node) {
      DownloadBook() => _buildBookRow(node as DownloadBook, indent),
      DownloadFolder() => _buildFolderRow(node as DownloadFolder, indent),
    };
  }

  Widget _buildBookRow(DownloadBook book, double indent) {
    final isChecked = checkedBooks.contains(book.link.url);
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: CheckboxListTile(
        value: isChecked,
        title: Text(book.entry.title),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (_) {
          final updated = Set<Uri>.from(checkedBooks);
          if (isChecked) {
            updated.remove(book.link.url);
          } else {
            updated.add(book.link.url);
          }
          onChanged(updated);
        },
      ),
    );
  }

  Widget _buildFolderRow(DownloadFolder folder, double indent) {
    final checkedCount = subtreeBooks.intersection(checkedBooks).length;
    final triState = checkedCount == 0
        ? false
        : checkedCount == subtreeBooks.length
            ? true
            : null; // indeterminate
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: CheckboxListTile(
        value: triState,
        tristate: true,
        title: Text(folder.title),
        secondary: const Icon(Icons.folder),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (_) {
          final updated = Set<Uri>.from(checkedBooks);
          if (triState == true || triState == null) {
            // checked or indeterminate → uncheck all
            updated.removeAll(subtreeBooks);
          } else {
            // unchecked → check all
            updated.addAll(subtreeBooks);
          }
          onChanged(updated);
        },
      ),
    );
  }
}

// ── Bottom bar ─────────────────────────────────────────────────────────────────

class _SelectionBottomBar extends StatelessWidget {
  const _SelectionBottomBar({
    required this.checkedBooks,
    required this.notifier,
  });

  final Set<Uri> checkedBooks;
  final FolderDownloadNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: checkedBooks.isEmpty
                ? null
                : () => notifier.confirmDownload(checkedBooks),
            child: Text('Download (${checkedBooks.length} books)'),
          ),
        ),
      ),
    );
  }
}

// ── Tree utilities ─────────────────────────────────────────────────────────────

/// Returns a flat list of (node, depth) pairs for building a ListView.
List<(DownloadTreeNode, int)> _flattenTree(DownloadTreeNode node, int depth) {
  return switch (node) {
    DownloadBook() => [(node, depth)],
    DownloadFolder() => [
        (node, depth),
        ...node.children.expand((c) => _flattenTree(c, depth + 1)),
      ],
  };
}

/// Collects all descendant book URLs under [node].
Set<Uri> _collectBookUrls(DownloadTreeNode node) {
  return switch (node) {
    DownloadBook() => {node.link.url},
    DownloadFolder() => node.children.fold(
        <Uri>{},
        (acc, c) => acc..addAll(_collectBookUrls(c)),
      ),
  };
}

// ── Download view ─────────────────────────────────────────────────────────────

class _DownloadView extends ConsumerWidget {
  const _DownloadView({required this.state});
  final FolderJobDownloading state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(folderDownloadProvider.notifier);
    final rows = _flattenTree(state.root, 0);
    final progress = state.total > 0 ? state.completedCount / state.total : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          notifier.cancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Downloading')),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final (node, depth) = rows[i];
                  if (node is! DownloadBook) {
                    return Padding(
                      padding: EdgeInsets.only(left: depth * 16.0),
                      child: ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text((node as DownloadFolder).title),
                      ),
                    );
                  }
                  final result = state.results[node.link.url];
                  final isCurrent = state.currentBook == node.link.url;
                  final icon = _bookIcon(node.link.url, isCurrent, result, context);
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: ListTile(
                      leading: icon,
                      title: Text(node.entry.title),
                    ),
                  );
                },
              ),
            ),
            _DownloadBottomBar(
              progress: progress,
              onCancel: notifier.cancel,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Done view ─────────────────────────────────────────────────────────────────

class _DoneView extends ConsumerWidget {
  const _DoneView({required this.state});
  final FolderJobDone state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = _flattenTree(state.root, 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Download complete')),
      body: Column(
        children: [
          if (state.wasCancelled)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Download was cancelled.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          if (state.stoppedAtLimit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Catalogue limit reached — not all books were scanned.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final (node, depth) = rows[i];
                if (node is! DownloadBook) {
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text((node as DownloadFolder).title),
                    ),
                  );
                }
                final result = state.results[node.link.url];
                final icon = _bookIcon(node.link.url, false, result, context);
                return Padding(
                  padding: EdgeInsets.only(left: depth * 16.0),
                  child: ListTile(
                    leading: icon,
                    title: Text(node.entry.title),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared book status icon ───────────────────────────────────────────────────

Widget _bookIcon(
    Uri linkUrl, bool isCurrent, BookDownloadResult? result, BuildContext context) {
  if (isCurrent) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
  if (result == null) {
    return const SizedBox(width: 24);
  }
  return switch (result.status) {
    BookDownloadStatus.done || BookDownloadStatus.skipped =>
      const Icon(Icons.check_circle, color: Colors.green),
    BookDownloadStatus.failed => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Download failed'),
            content: Text(result.error ?? 'Unknown error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
        child: const Icon(Icons.warning_rounded, color: Colors.red),
      ),
    BookDownloadStatus.downloading => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
  };
}

// ── Download bottom bar ───────────────────────────────────────────────────────

class _DownloadBottomBar extends StatelessWidget {
  const _DownloadBottomBar({required this.progress, required this.onCancel});
  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: progress)),
            const SizedBox(width: 16),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

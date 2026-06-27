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
      FolderJobDownloading() => const SizedBox.shrink(), // Task 8
      FolderJobDone() => const SizedBox.shrink(),        // Task 8
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

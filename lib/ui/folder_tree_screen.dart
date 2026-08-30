import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/download_selection.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/filter_chip_bar.dart';
import 'package:opds_browser/ui/widgets/nocturne_checkbox.dart';

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

// ── Selection view ───────────────────────────────────────────

class _SelectionView extends ConsumerStatefulWidget {
  const _SelectionView({required this.state});
  final FolderJobTreeReady state;

  @override
  ConsumerState<_SelectionView> createState() => _SelectionViewState();
}

class _SelectionViewState extends ConsumerState<_SelectionView> {
  /// Groups the reader has opened or closed by hand, by index. Anything not
  /// named here follows the default: the first group open, the rest closed.
  final Map<int, bool> _open = {};

  bool _isOpen(int index) => _open[index] ?? index == 0;

  void _toggleGroup(int index) {
    setState(() => _open[index] = !_isOpen(index));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(folderDownloadProvider.notifier);
    final groups = buildSelectionGroups(state.root);
    final checked = state.checkedBooks;
    final allUrls = {for (final g in groups) ...g.urls};

    // Pop the screen only when state reaches FolderJobIdle (produced by
    // reset() or an idle guard). Transitioning to FolderJobDownloading must
    // NOT pop — the screen switches to _DownloadView in place.
    ref.listen<FolderJobState>(folderDownloadProvider, (previous, next) {
      if (next is FolderJobIdle && context.mounted) {
        context.pop();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          notifier.reset();
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _SelectionHeader(
            rootTitle: switch (state.root) {
              DownloadFolder(:final title) => title,
              DownloadBook() => '',
            },
            groupCount: groups.length,
            bookCount: allUrls.length,
          ),
        ),
        body: Column(
          children: [
            if (state.stoppedAtLimit)
              Padding(
                padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                child: Text(
                  'Large catalogue — some content may not be shown'
                  ' (size limit reached).',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
              child: Row(
                children: [
                  NocturneChip(
                    label: 'All',
                    selected:
                        checked.length == allUrls.length && allUrls.isNotEmpty,
                    onTap: () => notifier.updateSelection(allUrls),
                  ),
                  const SizedBox(width: 7),
                  NocturneChip(
                    label: 'None',
                    selected: checked.isEmpty,
                    onTap: () => notifier.updateSelection(<Uri>{}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: groups.length,
                itemBuilder: (context, i) => _GroupCard(
                  group: groups[i],
                  checked: checked,
                  isOpen: _isOpen(i),
                  onToggleOpen: () => _toggleGroup(i),
                  onChanged: notifier.updateSelection,
                ),
              ),
            ),
            _SelectionBottomBar(
              checkedBooks: checked,
              totalCount: allUrls.length,
              notifier: notifier,
            ),
          ],
        ),
      ),
    );
  }
}

/// The two-line header: what the screen is, and what was scanned.
class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.rootTitle,
    required this.groupCount,
    required this.bookCount,
  });

  final String rootTitle;
  final int groupCount;
  final int bookCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = [
      if (rootTitle.isNotEmpty) rootTitle,
      '$groupCount ${groupCount == 1 ? 'group' : 'groups'}',
      '$bookCount ${bookCount == 1 ? 'book' : 'books'}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Select books',
          style: TextStyle(fontSize: 20, height: 1.2, color: scheme.onSurface),
        ),
        Text(
          parts.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// One group of books, drawn as a card that opens and closes.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.checked,
    required this.isOpen,
    required this.onToggleOpen,
    required this.onChanged,
  });

  final SelectionGroup group;
  final Set<Uri> checked;
  final bool isOpen;
  final VoidCallback onToggleOpen;
  final void Function(Set<Uri>) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final urls = group.urls;
    final selectedHere = urls.intersection(checked).length;
    final groupValue = selectedHere == 0
        ? false
        : selectedHere == urls.length
        ? true
        : null;

    final meta = [
      '${group.editionCount} '
          '${group.editionCount == 1 ? 'book' : 'books'}',
      if (selectedHere > 0 && selectedHere < urls.length)
        '$selectedHere selected',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        border: Border.all(color: palette.cardBorder),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onToggleOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
                    child: Row(
                      children: [
                        Icon(
                          isOpen
                              ? Icons.keyboard_arrow_down
                              : Icons.chevron_right,
                          size: 16,
                          color: palette.dim,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (group.title.isNotEmpty)
                                Text(
                                  group.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.3,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              Text(
                                meta,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.4,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: NocturneCheckbox(
                  value: groupValue,
                  semanticLabel: group.title.isEmpty
                      ? 'All books'
                      : group.title,
                  onTap: () {
                    final updated = Set<Uri>.from(checked);
                    if (groupValue == false) {
                      updated.addAll(urls);
                    } else {
                      updated.removeAll(urls);
                    }
                    onChanged(updated);
                  },
                ),
              ),
            ],
          ),
          if (isOpen)
            for (final book in group.books)
              _BookRow(book: book, checked: checked, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// One book inside a card — one row however many editions it stands for.
class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.book,
    required this.checked,
    required this.onChanged,
  });

  final FoldedBook book;
  final Set<Uri> checked;
  final void Function(Set<Uri>) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final isChecked = book.urls.every(checked.contains);

    void toggle() {
      final updated = Set<Uri>.from(checked);
      if (isChecked) {
        updated.removeAll(book.urls);
      } else {
        updated.addAll(book.urls);
      }
      onChanged(updated);
    }

    return InkWell(
      onTap: toggle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 3, 12, 3),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          children: [
            NocturneCheckbox(
              value: isChecked,
              semanticLabel: book.title,
              onTap: toggle,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (book.editionCount > 1)
                    Text(
                      '${book.editionCount} editions folded',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: palette.dim,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selection bottom bar ────────────────────────────────────────

class _SelectionBottomBar extends StatelessWidget {
  const _SelectionBottomBar({
    required this.checkedBooks,
    required this.totalCount,
    required this.notifier,
  });

  final Set<Uri> checkedBooks;
  final int totalCount;
  final FolderDownloadNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.cardSurface,
        border: Border(top: BorderSide(color: palette.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Text(
                  'Selected ${checkedBooks.length} of $totalCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: checkedBooks.isEmpty
                    ? null
                    : () => notifier.confirmDownload(checkedBooks),
                child: const Text('Download'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tree utilities ─────────────────────────────────────────────────────────────

/// Returns a flat list of (node, depth) pairs, skipping children of collapsed
/// folders.
List<(DownloadTreeNode, int)> _flattenTree(
  DownloadTreeNode node,
  int depth,
  Set<DownloadFolder> collapsed,
) {
  return switch (node) {
    DownloadBook() => [(node, depth)],
    DownloadFolder() => [
      (node, depth),
      if (!collapsed.contains(node))
        ...node.children.expand((c) => _flattenTree(c, depth + 1, collapsed)),
    ],
  };
}

/// Returns the total number of book descendants under [node].
int _countBooks(DownloadTreeNode node) => switch (node) {
  DownloadBook() => 1,
  DownloadFolder() => node.children.fold(0, (sum, c) => sum + _countBooks(c)),
};

// ── Download view ─────────────────────────────────────────────────────────────

class _DownloadView extends ConsumerStatefulWidget {
  const _DownloadView({required this.state});
  final FolderJobDownloading state;

  @override
  ConsumerState<_DownloadView> createState() => _DownloadViewState();
}

class _DownloadViewState extends ConsumerState<_DownloadView> {
  final Set<DownloadFolder> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(folderDownloadProvider.notifier);
    final rows = _flattenTree(state.root, 0, _collapsed);
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
                  if (node is DownloadFolder) {
                    final bookCount = _countBooks(node);
                    final isCollapsed = _collapsed.contains(node);
                    return Padding(
                      padding: EdgeInsets.only(left: depth * 16.0),
                      child: ListTile(
                        leading: Icon(
                          isCollapsed
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_down,
                        ),
                        title: Text(node.title),
                        subtitle: Text(
                          '$bookCount book${bookCount == 1 ? '' : 's'}',
                        ),
                        onTap: () => setState(() {
                          if (_collapsed.contains(node)) {
                            _collapsed.remove(node);
                          } else {
                            _collapsed.add(node);
                          }
                        }),
                      ),
                    );
                  }
                  final book = node as DownloadBook;
                  final result = state.results[book.link.url];
                  final isCurrent = state.currentBook == book.link.url;
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: ListTile(
                      leading: _bookIcon(
                        book.link.url,
                        isCurrent,
                        result,
                        context,
                      ),
                      title: Text(book.entry.title),
                    ),
                  );
                },
              ),
            ),
            _DownloadBottomBar(progress: progress, onCancel: notifier.cancel),
          ],
        ),
      ),
    );
  }
}

// ── Done view ─────────────────────────────────────────────────────────────────

class _DoneView extends ConsumerStatefulWidget {
  const _DoneView({required this.state});
  final FolderJobDone state;

  @override
  ConsumerState<_DoneView> createState() => _DoneViewState();
}

class _DoneViewState extends ConsumerState<_DoneView> {
  final Set<DownloadFolder> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(folderDownloadProvider.notifier);
    final rows = _flattenTree(state.root, 0, _collapsed);

    void closeAndReset() {
      notifier.reset();
      context.pop();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeAndReset();
      },
      child: Scaffold(
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
                  if (node is DownloadFolder) {
                    final bookCount = _countBooks(node);
                    final isCollapsed = _collapsed.contains(node);
                    return Padding(
                      padding: EdgeInsets.only(left: depth * 16.0),
                      child: ListTile(
                        leading: Icon(
                          isCollapsed
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_down,
                        ),
                        title: Text(node.title),
                        subtitle: Text(
                          '$bookCount book${bookCount == 1 ? '' : 's'}',
                        ),
                        onTap: () => setState(() {
                          if (_collapsed.contains(node)) {
                            _collapsed.remove(node);
                          } else {
                            _collapsed.add(node);
                          }
                        }),
                      ),
                    );
                  }
                  final book = node as DownloadBook;
                  final result = state.results[book.link.url];
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 16.0),
                    child: ListTile(
                      leading: _bookIcon(book.link.url, false, result, context),
                      title: Text(book.entry.title),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: closeAndReset,
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared book status icon ───────────────────────────────────────────────────

Widget _bookIcon(
  Uri linkUrl,
  bool isCurrent,
  BookDownloadResult? result,
  BuildContext context,
) {
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
    BookDownloadStatus.done => const Icon(
      Icons.check_circle,
      color: Colors.green,
    ),
    BookDownloadStatus.skipped => const Icon(Icons.skip_next),
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

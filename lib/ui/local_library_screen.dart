import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/local_library.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/widgets/edit_book_metadata_sheet.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class LocalLibraryState {}

class LibraryScanning extends LocalLibraryState {
  LibraryScanning({required this.scanned});
  final int scanned;
}

class LibraryReady extends LocalLibraryState {
  LibraryReady({required this.root, this.validationRun = false});
  final LibraryFolder root;
  final bool validationRun;

  LibraryReady copyWith({LibraryFolder? root, bool? validationRun}) =>
      LibraryReady(
        root: root ?? this.root,
        validationRun: validationRun ?? this.validationRun,
      );
}

class LibraryError extends LocalLibraryState {
  LibraryError(this.message);
  final String message;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class LocalLibraryNotifier extends Notifier<LocalLibraryState> {
  Completer<void>? _readyCompleter;

  @override
  LocalLibraryState build() {
    _readyCompleter = Completer<void>();
    unawaited(_scan());
    return LibraryScanning(scanned: 0);
  }

  /// Used in tests to await the first LibraryReady transition.
  Future<void> waitForReady() => _readyCompleter?.future ?? Future.value();

  Future<void> _scan() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      if (!ref.mounted) return;

      final treeUri = settings.target?.uriString;
      if (treeUri == null) {
        state = LibraryError('No library folder configured.');
        _completeReady();
        return;
      }

      final scanner = ref.read(localLibraryScannerProvider);
      final cache = ref.read(localLibraryCacheProvider);
      final parser = ref.read(fb2MetadataParserProvider);

      final files = <LibraryFile>[];
      await for (final file in scanner.scan(treeUri)) {
        if (!ref.mounted) return;
        files.add(file);
        state = LibraryScanning(scanned: files.length);
      }

      final metaMap = <String, LocalBookMetadata>{};
      for (final file in files) {
        final cached = await cache.get(file.relativePath);
        if (!ref.mounted) return;
        if (cached != null) {
          metaMap[file.relativePath] = cached;
        } else {
          try {
            final rw = ref.read(localBookReadWriterProvider);
            final bytes = await rw.readBytes(file.documentUri);
            final isZip = file.relativePath.toLowerCase().endsWith('.fb2.zip');
            final meta = parser.parseBytes(bytes, isZip: isZip);
            metaMap[file.relativePath] = meta;
            await cache.put(file.relativePath, meta);
          } catch (_) {
            final fallback = LocalBookMetadata(
              title: file.relativePath.split('/').last,
              author: '',
            );
            metaMap[file.relativePath] = fallback;
            await cache.put(file.relativePath, fallback);
            if (!ref.mounted) return;
          }
        }
        if (!ref.mounted) return;
      }

      final root = _buildTree(files, metaMap);
      if (!ref.mounted) return;
      state = LibraryReady(root: root);
    } catch (e) {
      if (!ref.mounted) return;
      state = LibraryError(e.toString());
    } finally {
      _completeReady();
    }
  }

  void _completeReady() {
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter!.complete();
    }
  }

  Future<void> updateBook(LibraryBook book, LocalBookMetadata newMeta) async {
    final rw = ref.read(localBookReadWriterProvider);
    final writer = ref.read(fb2MetadataWriterProvider);
    final cache = ref.read(localLibraryCacheProvider);

    final isZip = book.relativePath.toLowerCase().endsWith('.fb2.zip');
    final fileName = book.relativePath.split('/').last;
    final mimeType = isZip
        ? 'application/zip'
        : 'application/x-fictionbook+xml';

    final bytes = await rw.readBytes(book.documentUri);
    final patched = writer.patchBytes(bytes, newMeta, isZip: isZip);
    await rw.writeBytes(
      book.documentUri,
      book.parentUri,
      fileName,
      mimeType,
      patched,
    );
    await cache.put(book.relativePath, newMeta);

    final currentReady = state;
    if (currentReady is LibraryReady) {
      final newRoot = _replaceBook(
        currentReady.root,
        book.relativePath,
        (b) => b.copyWith(meta: newMeta),
      );
      state = currentReady.copyWith(root: newRoot);
    }
  }

  LibraryFolder _replaceBook(
    LibraryFolder folder,
    String relativePath,
    LibraryBook Function(LibraryBook) update,
  ) {
    final newChildren = folder.children.map((node) {
      return switch (node) {
        LibraryBook b when b.relativePath == relativePath => update(b),
        LibraryFolder f => _replaceBook(f, relativePath, update),
        _ => node,
      };
    }).toList();
    return folder.copyWith(children: newChildren);
  }

  void validate() {
    final current = state;
    if (current is! LibraryReady) return;
    const validator = LocalLibraryValidator();
    final annotated = validator.validate(current.root);
    state = current.copyWith(root: annotated, validationRun: true);
  }

  Future<(int fixed, int skipped)> fix() async {
    final current = state;
    if (current is! LibraryReady) return (0, 0);

    final rw = ref.read(localBookReadWriterProvider);
    final writer = ref.read(fb2MetadataWriterProvider);
    final cache = ref.read(localLibraryCacheProvider);

    final fixer = LocalLibraryFixer(
      readWriter: rw,
      writer: writer,
      cache: cache,
    );
    final (result, newRoot) = await fixer.fix(current.root);

    // Re-validate after fix to refresh isInvalid and hasWarning flags
    const validator = LocalLibraryValidator();
    final revalidated = validator.validate(newRoot);
    state = current.copyWith(root: revalidated, validationRun: true);

    return (result.fixed, result.skipped);
  }

  Future<void> refresh() async {
    final cache = ref.read(localLibraryCacheProvider);
    await cache.deleteAll();
    _readyCompleter = Completer<void>();
    state = LibraryScanning(scanned: 0);
    await _scan();
  }

  LibraryFolder _buildTree(
    List<LibraryFile> files,
    Map<String, LocalBookMetadata> metaMap,
  ) {
    final root = _FolderBuilder('');
    for (final file in files) {
      final segments = file.relativePath.split('/');
      final meta =
          metaMap[file.relativePath] ??
          LocalBookMetadata(title: segments.last, author: '');
      final book = LibraryBook(
        relativePath: file.relativePath,
        documentUri: file.documentUri,
        parentUri: file.parentUri,
        meta: meta,
      );
      root.addBook(segments.sublist(0, segments.length - 1), book);
    }
    return root.build();
  }
}

class _FolderBuilder {
  _FolderBuilder(this.name);
  final String name;
  final Map<String, _FolderBuilder> _subFolders = {};
  final List<LibraryBook> _books = [];

  void addBook(List<String> folderSegments, LibraryBook book) {
    if (folderSegments.isEmpty) {
      _books.add(book);
    } else {
      _subFolders
          .putIfAbsent(
            folderSegments.first,
            () => _FolderBuilder(folderSegments.first),
          )
          .addBook(folderSegments.sublist(1), book);
    }
  }

  LibraryFolder build() => LibraryFolder(
    name: name,
    children: [..._subFolders.values.map((f) => f.build()), ..._books],
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final localLibraryNotifierProvider =
    NotifierProvider<LocalLibraryNotifier, LocalLibraryState>(
      LocalLibraryNotifier.new,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});

  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  final Set<LibraryFolder> _collapsed = {};

  void _toggleFolder(LibraryFolder folder) {
    setState(() {
      if (_collapsed.contains(folder)) {
        _collapsed.remove(folder);
      } else {
        _collapsed.add(folder);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final libState = ref.watch(localLibraryNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: libState is LibraryScanning
                ? null
                : () =>
                      ref.read(localLibraryNotifierProvider.notifier).refresh(),
          ),
        ],
      ),
      body: switch (libState) {
        LibraryScanning(:final scanned) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Scanning… $scanned files found'),
            ],
          ),
        ),
        LibraryError(:final message) => Center(child: Text('Error: $message')),
        LibraryReady(:final root, :final validationRun) => _buildTree(
          root,
          validationRun,
        ),
      },
    );
  }

  Widget _buildTree(LibraryFolder root, bool validationRun) {
    // depth -1 so root children start at depth 0
    final rows = _flattenTree(root, -1, _collapsed);
    if (rows.isEmpty) {
      return const Center(child: Text('No books found in library.'));
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final (node, depth) = rows[i];
        return switch (node) {
          LibraryFolder() => _FolderTile(
            folder: node,
            depth: depth,
            validationRun: validationRun,
            isCollapsed: _collapsed.contains(node),
            onToggle: () => _toggleFolder(node),
          ),
          LibraryBook() => _BookTile(
            book: node,
            depth: depth,
            validationRun: validationRun,
          ),
        };
      },
    );
  }
}

List<(LibraryNode, int)> _flattenTree(
  LibraryNode node,
  int depth,
  Set<LibraryFolder> collapsed,
) {
  return switch (node) {
    LibraryBook() => [(node, depth)],
    LibraryFolder() => [
      if (depth >= 0) (node, depth),
      if (depth < 0 || !collapsed.contains(node))
        ...node.children.expand((c) => _flattenTree(c, depth + 1, collapsed)),
    ],
  };
}

// ── Folder tile ───────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.depth,
    required this.validationRun,
    required this.isCollapsed,
    required this.onToggle,
  });

  final LibraryFolder folder;
  final int depth;
  final bool validationRun;
  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bookCount = _countBooks(folder);
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        leading: Icon(
          isCollapsed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
        ),
        title: Text(folder.name),
        subtitle: Text('$bookCount book${bookCount == 1 ? '' : 's'}'),
        trailing: (validationRun && folder.hasWarning)
            ? const Icon(Icons.warning_amber_rounded, color: Colors.amber)
            : null,
        onTap: onToggle,
      ),
    );
  }
}

// ── Book tile ─────────────────────────────────────────────────────────────────

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.depth,
    required this.validationRun,
  });

  final LibraryBook book;
  final int depth;
  final bool validationRun;

  @override
  Widget build(BuildContext context) {
    final meta = book.meta;
    final seriesText = meta.series != null
        ? (meta.seriesIndex != null
              ? '${meta.series} #${meta.seriesIndex}'
              : meta.series!)
        : null;
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => EditBookMetadataSheet(book: book),
        ),
        leading: const Icon(Icons.book),
        title: Text(meta.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (meta.author.isNotEmpty) Text(meta.author),
            if (seriesText != null) Text(seriesText),
          ],
        ),
        isThreeLine: meta.author.isNotEmpty && seriesText != null,
        trailing: (validationRun && book.isInvalid)
            ? const Icon(Icons.warning_amber_rounded, color: Colors.amber)
            : null,
      ),
    );
  }
}

int _countBooks(LibraryNode node) => switch (node) {
  LibraryBook() => 1,
  LibraryFolder() => node.children.fold(0, (sum, c) => sum + _countBooks(c)),
};

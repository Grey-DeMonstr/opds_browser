import 'dart:typed_data';
import 'package:opds_browser/data/fb2_metadata_writer.dart';
import 'package:opds_browser/data/sqflite_local_library_cache.dart';

class LocalBookMetadata {
  const LocalBookMetadata({
    required this.title,
    required this.author,
    this.series,
    this.seriesIndex,
  });

  final String title;
  final String author;
  final String? series;
  final int? seriesIndex;

  LocalBookMetadata copyWith({
    String? title,
    String? author,
    String? series,
    int? seriesIndex,
    bool clearSeries = false,
    bool clearSeriesIndex = false,
  }) => LocalBookMetadata(
    title: title ?? this.title,
    author: author ?? this.author,
    series: clearSeries ? null : (series ?? this.series),
    seriesIndex: clearSeriesIndex ? null : (seriesIndex ?? this.seriesIndex),
  );
}

class LibraryFile {
  const LibraryFile({
    required this.relativePath,
    required this.documentUri,
    required this.parentUri,
  });

  final String relativePath; // e.g. "Jane Doe/Series/book.fb2"
  final String documentUri; // SAF document URI for reading
  final String parentUri; // SAF directory URI for writing
}

sealed class LibraryNode {}

class LibraryFolder extends LibraryNode {
  LibraryFolder({
    required this.name,
    required this.children,
    this.hasWarning = false,
  });

  final String name;
  final List<LibraryNode> children;
  final bool hasWarning;

  LibraryFolder copyWith({List<LibraryNode>? children, bool? hasWarning}) =>
      LibraryFolder(
        name: name,
        children: children ?? this.children,
        hasWarning: hasWarning ?? this.hasWarning,
      );
}

class LibraryBook extends LibraryNode {
  LibraryBook({
    required this.relativePath,
    required this.documentUri,
    required this.parentUri,
    required this.meta,
    this.isInvalid = false,
  });

  final String relativePath;
  final String documentUri;
  final String parentUri;
  final LocalBookMetadata meta;
  final bool isInvalid;

  LibraryBook copyWith({LocalBookMetadata? meta, bool? isInvalid}) =>
      LibraryBook(
        relativePath: relativePath,
        documentUri: documentUri,
        parentUri: parentUri,
        meta: meta ?? this.meta,
        isInvalid: isInvalid ?? this.isInvalid,
      );
}

abstract interface class LocalLibraryScanner {
  Stream<LibraryFile> scan(String treeUri);
}

class LocalLibraryValidator {
  const LocalLibraryValidator();

  /// Returns a new annotated tree. Pure function — no I/O.
  LibraryFolder validate(LibraryFolder root) {
    return _annotateFolder(root);
  }

  LibraryFolder _annotateFolder(LibraryFolder folder) {
    final annotatedChildren = folder.children.map(_annotateNode).toList();
    final hasWarning = annotatedChildren.any(
      (node) => switch (node) {
        LibraryBook b => b.isInvalid,
        LibraryFolder f => f.hasWarning,
      },
    );
    return folder.copyWith(children: annotatedChildren, hasWarning: hasWarning);
  }

  LibraryNode _annotateNode(LibraryNode node) => switch (node) {
    LibraryBook b => b.copyWith(isInvalid: !_isValid(b)),
    LibraryFolder f => _annotateFolder(f),
  };

  bool _isValid(LibraryBook book) {
    final parts = book.relativePath.split('/');
    // Last part is the filename; preceding parts are folder segments
    final segments = parts.sublist(0, parts.length - 1);
    final depth = segments.length;
    final author = book.meta.author.toLowerCase().trim();
    final series = book.meta.series?.toLowerCase().trim();

    return switch (depth) {
      0 => false,
      1 => series == null && segments[0].toLowerCase().trim() == author,
      2 =>
        series != null &&
            segments[0].toLowerCase().trim() == author &&
            segments[1].toLowerCase().trim() == series,
      _ => false,
    };
  }
}

abstract interface class LocalBookReadWriter {
  Future<Uint8List> readBytes(String documentUri);

  /// Overwrites the existing file identified by [documentUri].
  /// [parentUri] and [fileName] identify the location for write-back.
  /// [mimeType] is 'application/x-fictionbook+xml' for .fb2,
  /// 'application/zip' for .fb2.zip.
  Future<void> writeBytes(
    String documentUri,
    String parentUri,
    String fileName,
    String mimeType,
    Uint8List bytes,
  );
}

class FixResult {
  final int fixed;
  final int skipped;
  const FixResult({required this.fixed, required this.skipped});
}

class LocalLibraryFixer {
  final LocalBookReadWriter readWriter;
  final Fb2MetadataWriter writer;
  final SqfliteLocalLibraryCache cache;

  const LocalLibraryFixer({
    required this.readWriter,
    required this.writer,
    required this.cache,
  });

  Future<(FixResult, LibraryFolder)> fix(LibraryFolder root) async {
    var fixed = 0;
    var skipped = 0;

    Future<LibraryFolder> processFolder(LibraryFolder folder) async {
      final newChildren = <LibraryNode>[];
      for (final node in folder.children) {
        switch (node) {
          case LibraryBook b when b.isInvalid:
            final result = await _fixBook(b);
            if (result != null) {
              newChildren.add(b.copyWith(meta: result, isInvalid: false));
              fixed++;
            } else {
              newChildren.add(b);
              skipped++;
            }
          case LibraryFolder f:
            newChildren.add(await processFolder(f));
          default:
            newChildren.add(node);
        }
      }
      return folder.copyWith(children: newChildren);
    }

    final newRoot = await processFolder(root);
    final revalidated = const LocalLibraryValidator().validate(newRoot);
    return (FixResult(fixed: fixed, skipped: skipped), revalidated);
  }

  Future<LocalBookMetadata?> _fixBook(LibraryBook book) async {
    final parts = book.relativePath.split('/');
    final segments = parts.sublist(0, parts.length - 1);
    final depth = segments.length;

    final LocalBookMetadata newMeta;
    switch (depth) {
      case 0:
        return null;
      case 1:
        newMeta = book.meta.copyWith(
          author: segments[0],
          clearSeries: true,
          clearSeriesIndex: true,
        );
      case 2:
        newMeta = book.meta.copyWith(author: segments[0], series: segments[1]);
      default:
        return null;
    }

    final isZip = book.relativePath.toLowerCase().endsWith('.fb2.zip');
    final fileName = parts.last;
    final mimeType = isZip
        ? 'application/zip'
        : 'application/x-fictionbook+xml';

    final bytes = await readWriter.readBytes(book.documentUri);
    final patched = writer.patchBytes(bytes, newMeta, isZip: isZip);
    await readWriter.writeBytes(
      book.documentUri,
      book.parentUri,
      fileName,
      mimeType,
      patched,
    );
    await cache.put(book.relativePath, newMeta);
    return newMeta;
  }
}

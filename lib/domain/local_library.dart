import 'dart:typed_data';

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

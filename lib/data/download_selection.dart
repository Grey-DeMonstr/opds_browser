import 'package:opds_browser/data/folder_download_job.dart';

/// One row of the selection list: a book title, standing for every edition of
/// it the catalogue listed.
///
/// Large catalogues list the same book many times over — one entry per scan,
/// per uploader, per format. The row covers all of them at once, so choosing a
/// book means choosing the book rather than choosing between its copies.
class FoldedBook {
  final String title;

  /// Every acquisition link this row stands for.
  final Set<Uri> urls;

  const FoldedBook({required this.title, required this.urls});

  /// How many listings folded into this row. 1 means nothing was folded.
  int get editionCount => urls.length;
}

/// A card in the selection list — the books held by one folder of the scan.
class SelectionGroup {
  final String title;
  final List<FoldedBook> books;

  const SelectionGroup({required this.title, required this.books});

  /// Every link in the group, across all its rows.
  Set<Uri> get urls => {for (final book in books) ...book.urls};

  /// How many listings the group covers — folded rows counted in full.
  int get editionCount => books.fold(0, (n, b) => n + b.editionCount);
}

/// Turns a scanned download tree into the flat list of groups the selection
/// screen draws.
///
/// Every folder that directly holds books becomes one group, however deep it
/// sits, and the books inside it are folded by title. Folders that only hold
/// other folders contribute nothing themselves — their children speak for them.
List<SelectionGroup> buildSelectionGroups(DownloadTreeNode root) {
  final groups = <SelectionGroup>[];

  void visit(DownloadTreeNode node) {
    switch (node) {
      case DownloadBook():
        groups.add(SelectionGroup(title: '', books: _fold([node])));
      case DownloadFolder(:final title, :final children):
        final books = children.whereType<DownloadBook>().toList();
        if (books.isNotEmpty) {
          groups.add(SelectionGroup(title: title, books: _fold(books)));
        }
        for (final child in children.whereType<DownloadFolder>()) {
          visit(child);
        }
    }
  }

  visit(root);
  return groups;
}

/// Folds [books] by title, keeping the order each title first appeared in.
List<FoldedBook> _fold(List<DownloadBook> books) {
  final urlsByTitle = <String, Set<Uri>>{};
  for (final book in books) {
    (urlsByTitle[book.entry.title] ??= <Uri>{}).add(book.link.url);
  }
  return [
    for (final entry in urlsByTitle.entries)
      FoldedBook(title: entry.key, urls: entry.value),
  ];
}

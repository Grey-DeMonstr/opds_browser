import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/data/download_selection.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/models.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

DownloadBook _book(String title, String url) => DownloadBook(
  entry: BookEntry(title: title, authors: const [], acquisitionLinks: const []),
  link: AcquisitionLink(
    url: Uri.parse(url),
    mimeType: 'application/fb2+zip',
    formatLabel: 'FB2',
  ),
);

DownloadFolder _folder(String title, List<DownloadTreeNode> children) =>
    DownloadFolder(title: title, children: children);

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  test('books directly under the root form a group under its title', () {
    final root = _folder('Dickens, Charles', [
      _book('Oliver Twist', 'https://e.org/1'),
    ]);

    final groups = buildSelectionGroups(root);

    expect(groups, hasLength(1));
    expect(groups.single.title, 'Dickens, Charles');
    expect(groups.single.books.single.title, 'Oliver Twist');
  });

  test('each folder holding books becomes its own group', () {
    final root = _folder('', [
      _folder('Series: Barsetshire', [_book('The Warden', 'https://e.org/1')]),
      _folder('Series: Sherlock Holmes', [
        _book('Oliver Twist', 'https://e.org/2'),
      ]),
    ]);

    expect(buildSelectionGroups(root).map((g) => g.title), [
      'Series: Barsetshire',
      'Series: Sherlock Holmes',
    ]);
  });

  test('a folder holding only subfolders contributes no group of its own', () {
    final root = _folder('root', [
      _folder('Series', [
        _folder('Barsetshire', [_book('The Warden', 'https://e.org/1')]),
      ]),
    ]);

    expect(buildSelectionGroups(root).map((g) => g.title), ['Barsetshire']);
  });

  test('repeated editions of one title fold into a single row', () {
    final root = _folder('Barsetshire Chronicles', [
      _book('Great Expectations', 'https://e.org/1'),
      _book('Great Expectations', 'https://e.org/2'),
      _book('Great Expectations', 'https://e.org/3'),
    ]);

    final book = buildSelectionGroups(root).single.books.single;

    expect(book.title, 'Great Expectations');
    expect(book.editionCount, 3);
    expect(book.urls, {
      Uri.parse('https://e.org/1'),
      Uri.parse('https://e.org/2'),
      Uri.parse('https://e.org/3'),
    });
  });

  test('a single edition folds nothing', () {
    final root = _folder('s', [_book('Oliver Twist', 'https://e.org/1')]);

    expect(buildSelectionGroups(root).single.books.single.editionCount, 1);
  });

  test('the same title in two groups stays two rows', () {
    final root = _folder('', [
      _folder('Series 1', [_book('Oliver Twist', 'https://e.org/1')]),
      _folder('Series 2', [_book('Oliver Twist', 'https://e.org/2')]),
    ]);

    final groups = buildSelectionGroups(root);

    expect(groups.map((g) => g.books.single.urls), [
      {Uri.parse('https://e.org/1')},
      {Uri.parse('https://e.org/2')},
    ]);
  });

  test('rows keep the order the catalogue listed them in', () {
    final root = _folder('s', [
      _book('Bleak House', 'https://e.org/1'),
      _book('Great Expectations', 'https://e.org/2'),
      _book('Bleak House', 'https://e.org/3'),
    ]);

    expect(buildSelectionGroups(root).single.books.map((b) => b.title), [
      'Bleak House',
      'Great Expectations',
    ]);
  });

  test('a group counts every edition it covers, not its folded rows', () {
    final root = _folder('s', [
      _book('Great Expectations', 'https://e.org/1'),
      _book('Great Expectations', 'https://e.org/2'),
      _book('Oliver Twist', 'https://e.org/3'),
    ]);

    final group = buildSelectionGroups(root).single;

    expect(group.books, hasLength(2));
    expect(group.editionCount, 3);
    expect(group.urls, hasLength(3));
  });

  test('an empty tree has no groups', () {
    expect(buildSelectionGroups(_folder('', [])), isEmpty);
  });

  test('a bare book at the root forms a group with no title', () {
    expect(
      buildSelectionGroups(
        _book('Oliver Twist', 'https://e.org/1'),
      ).single.title,
      '',
    );
  });
}

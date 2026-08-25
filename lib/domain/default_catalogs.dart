/// A catalogue every fresh install starts with, so the app has something to
/// browse before the user adds one of their own.
class DefaultCatalog {
  final String title;
  final String rootUrl;

  const DefaultCatalog({required this.title, required this.rootUrl});
}

/// Seeded into the catalogues table when the database is first created.
/// Existing installs are left alone — a user who deleted one of these should
/// not see it return after an update.
const defaultCatalogs = <DefaultCatalog>[
  DefaultCatalog(
    title: 'Project Gutenberg',
    // The navigation root — Popular, Latest, browse by author/title/language.
    // Not /ebooks/search.opds/, which is the flat "All Books" list.
    rootUrl: 'https://www.gutenberg.org/ebooks.opds/',
  ),
];

/// The kinds of section a catalogue root commonly offers.
enum EntryGlyph {
  author,
  series,
  title,
  genre,
  popular,
  newest,
  random,
  folder,
}

/// Keywords per glyph, in the order they are tried.
const _keywords = <EntryGlyph, List<String>>{
  EntryGlyph.author: ['author', 'avtor', 'writer'],
  EntryGlyph.series: ['series', 'serie', 'sequence', 'cycle'],
  EntryGlyph.genre: ['genre', 'category', 'subject', 'shelf', 'bookshelf'],
  EntryGlyph.title: ['title', 'alphabet'],
  EntryGlyph.popular: ['popular', 'downloads', 'downloaded'],
  EntryGlyph.newest: ['newest', 'latest', 'recent', 'release_date'],
  EntryGlyph.random: ['random', 'shuffle'],
};

/// The glyph [url] earns, inferred from the link itself.
///
/// OPDS carries no icon for an entry, and matching on the title would need a
/// mapping per catalogue and per language — "По жанрам" and "Genres" are the
/// same section. The href is neither: catalogues name these paths in English
/// whatever language they publish in.
///
/// Matching is per path segment and by prefix, never anywhere in the string.
/// A substring match would read `/ebooks/` — the root of a catalogue whose
/// every section lives under it — as a section about books, and give the whole
/// root one glyph.
///
/// Some catalogues put the section in the query instead, hanging every row off
/// one path and telling them apart by a sort order. Those are matched on the
/// whole value, so a query carrying someone's search terms cannot pick a
/// glyph out of them.
EntryGlyph glyphForEntryUrl(Uri url) {
  final segments = [
    for (final s in url.pathSegments)
      if (s.isNotEmpty) s.toLowerCase(),
  ];
  for (final MapEntry(key: glyph, value: words) in _keywords.entries) {
    for (final segment in segments) {
      for (final word in words) {
        if (segment.startsWith(word)) return glyph;
      }
    }
  }

  // Some catalogues express the section as a query instead of a path.
  final values = url.queryParameters.values.map((v) => v.toLowerCase());
  for (final MapEntry(key: glyph, value: words) in _keywords.entries) {
    for (final value in values) {
      for (final word in words) {
        if (value == word) return glyph;
      }
    }
  }

  return EntryGlyph.folder;
}

import 'package:opds_browser/domain/models.dart';

/// The count and the unit that make up an OPDS navigation subtitle.
///
/// Catalogues write these as `930 authors` or `1 book by this author`; the browse
/// list draws the number and the word in separate columns so numbers of
/// different width still line up.
typedef EntryCount = ({String count, String unit});

final _leadingCount = RegExp(r'^\s*(\d+)\s*(.*)$', dotAll: true);

/// Splits [subtitle] into its leading count and the unit that follows.
///
/// Text that does not open with a number keeps its whole self as the unit, so
/// nothing a catalogue wrote is ever dropped.
EntryCount splitEntryCount(String? subtitle) {
  final text = subtitle?.trim() ?? '';
  if (text.isEmpty) return (count: '', unit: '');
  final match = _leadingCount.firstMatch(text);
  if (match == null) return (count: '', unit: text);
  return (count: match.group(1)!, unit: match.group(2)!.trim());
}

/// True when [title] names a prefix bucket — one of the alphabetic grouping
/// folders a large catalogue synthesises, such as `DIC~`.
///
/// Buckets are catalogue scaffolding rather than entries someone chose to
/// publish, so the list sets them apart instead of giving them an icon.
bool isPrefixBucket(String title) => title.trimRight().endsWith('~');

/// The title [entry] shows in the browse list, whichever kind it is.
String browseEntryTitle(FeedEntry entry) => switch (entry) {
  NavigationEntry e => e.title,
  BookEntry e => e.title,
};

/// Narrows [entries] to what the browse list should show.
///
/// [bucketsHidden] drops the synthesised prefix buckets, leaving the entries
/// someone actually published; [query] keeps only titles containing it,
/// compared without case.
List<FeedEntry> filterBrowseEntries(
  List<FeedEntry> entries, {
  required bool bucketsHidden,
  required String query,
}) {
  final needle = query.trim().toLowerCase();
  return entries.where((entry) {
    final title = browseEntryTitle(entry);
    if (bucketsHidden && entry is NavigationEntry && isPrefixBucket(title)) {
      return false;
    }
    return needle.isEmpty || title.toLowerCase().contains(needle);
  }).toList();
}

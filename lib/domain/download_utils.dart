import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';

/// Returns the preferred [AcquisitionLink] to download without showing a picker,
/// or null when a picker is required (multiple links, none is FB2 or FB2.ZIP).
/// Preference order: FB2.ZIP > FB2 > (null = picker needed).
AcquisitionLink? preferredLink(List<AcquisitionLink> links) {
  if (links.isEmpty) return null;
  if (links.length == 1) return links.first;
  final fb2zip = links.where((l) => l.formatLabel == 'FB2.ZIP').firstOrNull;
  if (fb2zip != null) return fb2zip;
  final fb2 = links.where((l) => l.formatLabel == 'FB2').firstOrNull;
  return fb2; // null when no FB2 variant → caller shows format picker
}

/// Builds the sanitized download filename for [entry] in [link]'s format.
/// Pattern: `<Authors> - [<Series> #<Index> - ]<Title>.<ext>`
/// Capped at 200 characters (truncates title segment, preserves extension).
String buildFileName(BookEntry entry, AcquisitionLink link) {
  final parts = <String>[];
  final authors = _authorString(entry.authors);
  if (authors != null) parts.add(authors);
  if (entry.series != null) {
    final idx = entry.seriesIndex;
    parts.add(idx != null
        ? '${entry.series} #${_formatIndex(idx)}'
        : entry.series!);
  }
  parts.add(entry.title);
  final ext = _formatExt(link.formatLabel);
  var name = _sanitize('${parts.join(' - ')}.$ext');
  if (name.length > 200) {
    final suffix = '.$ext';
    name = '${name.substring(0, 200 - suffix.length)}$suffix';
  }
  return name;
}

/// Returns the list of subdirectory segments to place between the storage root
/// and the filename, based on [settings]. Returns an empty list when no
/// folder-per-author/series data is available.
List<String> buildPathSegments(AppSettings settings, BookEntry entry) {
  final segments = <String>[];
  final authors = _authorString(entry.authors);
  if (settings.createAuthorFolder && authors != null) {
    segments.add(_sanitize(authors));
  }
  if (settings.createSeriesFolder && entry.series != null) {
    segments.add(_sanitize(entry.series!));
  }
  return segments;
}

String? _authorString(List<String> authors) {
  if (authors.isEmpty) return null;
  if (authors.length == 1) return authors.first;
  if (authors.length == 2) return '${authors[0]}, ${authors[1]}';
  return '${authors.first} et al.';
}

String _formatIndex(double idx) =>
    idx == idx.truncateToDouble() ? idx.toInt().toString() : idx.toString();

String _formatExt(String label) =>
    label == 'FB2.ZIP' ? 'fb2.zip' : label.toLowerCase();

String _sanitize(String s) => s
    .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

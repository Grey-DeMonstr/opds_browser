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

/// Selects the best [AcquisitionLink] for an automated folder download.
/// Unlike [preferredLink], never returns null — falls back to EPUB > PDF >
/// MOBI > first listed when no FB2 variant is present.
AcquisitionLink folderPreferredLink(List<AcquisitionLink> links) {
  assert(links.isNotEmpty);
  final preferred = preferredLink(links);
  if (preferred != null) return preferred;
  const priority = ['EPUB', 'PDF', 'MOBI'];
  for (final label in priority) {
    final match = links.where((l) => l.formatLabel == label).firstOrNull;
    if (match != null) return match;
  }
  return links.first;
}

/// Extracts the `series` query parameter from [url] as the inferred series
/// name, or null when the parameter is absent or empty.
String? inferSeriesFromUrl(Uri url) {
  final value = url.queryParameters['series'];
  return (value != null && value.isNotEmpty) ? value : null;
}

/// Builds the sanitized download filename for [entry] in [link]'s format.
/// Author and series segments are omitted when [settings] indicates they are
/// already encoded in the folder path (createAuthorFolder / createSeriesFolder).
/// Pattern: `[<Authors> - ][<Series> #<Index> - ]<Title>.<ext>`
/// Capped at 200 characters (truncates title segment, preserves extension).
String buildFileName(
  BookEntry entry,
  AcquisitionLink link,
  AppSettings settings, {
  String? inferredSeries,
}) {
  final parts = <String>[];
  final authors = _authorString(entry.authors);
  if (authors != null && !settings.createAuthorFolder) parts.add(authors);
  final effectiveSeries = entry.series ?? inferredSeries;
  if (effectiveSeries != null && !settings.createSeriesFolder) {
    final idx = entry.seriesIndex;
    parts.add(idx != null
        ? '$effectiveSeries #${_formatIndex(idx)}'
        : effectiveSeries);
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
List<String> buildPathSegments(
  AppSettings settings,
  BookEntry entry, {
  String? inferredSeries,
}) {
  final segments = <String>[];
  final authors = _authorString(entry.authors);
  if (settings.createAuthorFolder && authors != null) {
    segments.add(_sanitize(authors));
  }
  final effectiveSeries = entry.series ?? inferredSeries;
  if (settings.createSeriesFolder && effectiveSeries != null) {
    segments.add(_sanitize(effectiveSeries));
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

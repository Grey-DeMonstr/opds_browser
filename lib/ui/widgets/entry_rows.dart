import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/browse_list.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/require_library_folder.dart';
import 'package:opds_browser/ui/theme.dart';

String _formatSeriesIndex(double idx) =>
    idx == idx.truncateToDouble() ? idx.toInt().toString() : idx.toString();

/// A folder row: the title verbatim, with what the catalogue said is inside on
/// a quieter line beneath it.
///
/// The count and its unit read as one phrase there — "930 authors" — with the
/// number picked out. They sat in fixed right-hand columns until anything
/// longer than a word ("1 book by this author", or a book row's author name)
/// arrived and was ellipsised to nothing legible.
class NavigationEntryRow extends StatelessWidget {
  final NavigationEntry entry;
  final int catalogId;
  final String? inferredSeries;

  const NavigationEntryRow({
    required this.entry,
    required this.catalogId,
    this.inferredSeries,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final isBucket = isPrefixBucket(entry.title);
    final (count: count, unit: unit) = splitEntryCount(entry.subtitle);

    final seriesParam = inferredSeries != null
        ? '&series=${Uri.encodeComponent(inferredSeries!)}'
        : '';
    final subtitleParam = entry.subtitle != null
        ? '&subtitle=${Uri.encodeComponent(entry.subtitle!)}'
        : '';

    return InkWell(
      onTap: () => context.push(
        '/browse?catalogId=$catalogId&url=${Uri.encodeComponent(entry.url.toString())}'
        '&title=${Uri.encodeComponent(entry.title)}$subtitleParam$seriesParam',
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: isBucket
                  ? TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.58,
                      color: palette.bucketLabel,
                    )
                  : TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
            ),
            if (count.isNotEmpty || unit.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (count.isNotEmpty)
                        TextSpan(
                          text: count,
                          // Picked out by colour alone. It was monospace while
                          // it held its own column, to line figures up; inline
                          // in a phrase that buys nothing and only makes the
                          // digits sit oddly against the word beside them.
                          style: TextStyle(color: palette.countText),
                        ),
                      if (count.isNotEmpty && unit.isNotEmpty)
                        const TextSpan(text: ' '),
                      if (unit.isNotEmpty) TextSpan(text: unit),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: palette.dim,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BookEntryTile extends ConsumerStatefulWidget {
  final BookEntry entry;
  final String? inferredSeries;

  const BookEntryTile({required this.entry, this.inferredSeries, super.key});

  @override
  ConsumerState<BookEntryTile> createState() => BookEntryTileState();
}

class BookEntryTileState extends ConsumerState<BookEntryTile> {
  Uri? _downloadUrl;

  Uri get _defaultWatchUrl =>
      (preferredLink(widget.entry.acquisitionLinks) ??
              widget.entry.acquisitionLinks.first)
          .url;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final authors = entry.authors.join(', ');
    final effectiveSeries = entry.series ?? widget.inferredSeries;
    final isInferredSeries = entry.series == null && effectiveSeries != null;
    final seriesText = effectiveSeries != null
        ? (entry.seriesIndex != null
              ? '$effectiveSeries #${_formatSeriesIndex(entry.seriesIndex!)}'
              : effectiveSeries)
        : null;

    final hasLinks = entry.acquisitionLinks.isNotEmpty;
    DownloadState? downloadState;
    if (hasLinks) {
      final watchUrl = _downloadUrl ?? _defaultWatchUrl;
      downloadState = ref.watch(downloadNotifierProvider(watchUrl));
      ref.listen(downloadNotifierProvider(watchUrl), (_, state) {
        if (state is DownloadFailed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: ${state.message}')),
          );
        }
      });
    }
    final isDownloading = downloadState is DownloadInProgress;

    return ListTile(
      onTap: () => showBookDetailsSheet(context, entry),
      leading: SizedBox(
        width: 56,
        height: 80,
        child: entry.coverUrl != null
            ? CachedNetworkImage(
                imageUrl: entry.coverUrl!.toString(),
                fit: BoxFit.cover,
                placeholder: (_, _) => const Icon(Icons.book),
                errorWidget: (_, _, _) => const Icon(Icons.book),
              )
            : const Icon(Icons.book),
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (authors.isNotEmpty) Text(authors),
          // The third line carries the series when there is one, and otherwise
          // the description. Catalogues that publish several editions of one
          // book — Project Gutenberg lists a stripped and an illustrated
          // edition under the same title — are told apart only by that text.
          if (seriesText != null)
            Text(
              seriesText,
              style: isInferredSeries
                  ? const TextStyle(fontStyle: FontStyle.italic)
                  : null,
            )
          else
            Text(
              entry.summary ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      isThreeLine: authors.isNotEmpty,
      trailing: hasLinks
          ? isDownloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: _onDownloadTap,
                  )
          : null,
    );
  }

  // Uses the State's own context throughout, so the `mounted` guards after
  // each await are the ones the analyzer expects.
  Future<void> _onDownloadTap() async {
    if (!await ensureLibraryFolder(context, ref)) return;
    if (!mounted) return;
    final entry = widget.entry;
    // Read after the gate: it may have just set the folder.
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final preferred = preferredLink(entry.acquisitionLinks);
    if (preferred != null) {
      setState(() => _downloadUrl = preferred.url);
      ref
          .read(downloadNotifierProvider(preferred.url).notifier)
          .start(entry, settings, inferredSeries: widget.inferredSeries);
    } else {
      final chosen = await _showFormatPicker(context, entry.acquisitionLinks);
      if (chosen == null || !mounted) return;
      setState(() => _downloadUrl = chosen.url);
      ref
          .read(downloadNotifierProvider(chosen.url).notifier)
          .start(entry, settings, inferredSeries: widget.inferredSeries);
    }
  }

  Future<AcquisitionLink?> _showFormatPicker(
    BuildContext context,
    List<AcquisitionLink> links,
  ) {
    return showDialog<AcquisitionLink>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: links
              .map(
                (l) => TextButton(
                  onPressed: () => Navigator.of(ctx).pop(l),
                  child: Text(l.formatLabel),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/providers.dart';

class BookDetailsSheet extends ConsumerStatefulWidget {
  const BookDetailsSheet({required this.entry, super.key});

  final BookEntry entry;

  @override
  ConsumerState<BookDetailsSheet> createState() => _BookDetailsSheetState();
}

class _BookDetailsSheetState extends ConsumerState<BookDetailsSheet> {
  Uri? _activeDownloadUrl;

  Uri get _defaultWatchUrl =>
      (preferredLink(widget.entry.acquisitionLinks) ??
              widget.entry.acquisitionLinks.first)
          .url;

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).value ??
        const AppSettings(target: SystemDownloads());
    final watchUrl = _activeDownloadUrl ?? _defaultWatchUrl;
    final downloadState = ref.watch(downloadNotifierProvider(watchUrl));
    final isDownloading = downloadState is DownloadInProgress;

    ref.listen(downloadNotifierProvider(watchUrl), (_, state) {
      if (state is DownloadFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${state.message}'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => ref
                  .read(downloadNotifierProvider(watchUrl).notifier)
                  .start(widget.entry, settings),
            ),
          ),
        );
      }
    });

    final entry = widget.entry;
    final preferred = preferredLink(entry.acquisitionLinks);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(
                width: 120,
                height: 170,
                child: entry.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: entry.coverUrl!.toString(),
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const Icon(Icons.book, size: 48),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.book, size: 48),
                      )
                    : const Icon(Icons.book, size: 48),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              entry.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (entry.authors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.authors.join(', ')),
            ],
            if (entry.series != null) ...[
              const SizedBox(height: 4),
              Text(_seriesText(entry)),
            ],
            if (entry.summary != null) ...[
              const SizedBox(height: 8),
              Text(entry.summary!),
            ],
            const Divider(height: 24),
            Center(
              child: isDownloading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () =>
                          _onDownloadTap(context, entry, preferred, settings),
                      child: const Text('Download'),
                    ),
            ),
            const SizedBox(height: 8),
            ...entry.acquisitionLinks
                .where((link) => link != preferred)
                .map(
                  (link) => ListTile(
                    title: Text(link.formatLabel),
                    onTap: isDownloading
                        ? null
                        : () {
                            setState(() => _activeDownloadUrl = link.url);
                            ref
                                .read(
                                  downloadNotifierProvider(link.url).notifier,
                                )
                                .start(entry, settings);
                          },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDownloadTap(
    BuildContext context,
    BookEntry entry,
    AcquisitionLink? preferred,
    AppSettings settings,
  ) async {
    if (preferred != null) {
      setState(() => _activeDownloadUrl = preferred.url);
      ref
          .read(downloadNotifierProvider(preferred.url).notifier)
          .start(entry, settings);
    } else {
      final chosen = await _showFormatPicker(context, entry.acquisitionLinks);
      if (chosen == null || !mounted) return;
      setState(() => _activeDownloadUrl = chosen.url);
      ref
          .read(downloadNotifierProvider(chosen.url).notifier)
          .start(entry, settings);
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

  String _seriesText(BookEntry entry) {
    final idx = entry.seriesIndex;
    if (idx == null) return entry.series!;
    final idxStr = idx == idx.truncateToDouble()
        ? idx.toInt().toString()
        : idx.toString();
    return '${entry.series} #$idxStr';
  }
}

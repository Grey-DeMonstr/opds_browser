import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/android_file_opener.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/time_formatter.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/providers.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  final int catalogId;
  final Uri url;
  final String? navTitle;
  final String? inferredSeries;

  const BrowseScreen({
    required this.catalogId,
    required this.url,
    this.navTitle,
    this.inferredSeries,
    super.key,
  });

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  BrowseArgs get _args => (widget.catalogId, widget.url);

  Future<void> _refresh() async {
    try {
      await ref.read(browseProvider(_args).notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final browseAsync = ref.watch(browseProvider(_args));
    final isFavorite = ref.watch(isFavoriteProvider(_args));

    return browseAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $e'),
              TextButton(
                onPressed: () => ref.invalidate(browseProvider(_args)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (state) => _BrowseContent(
        args: _args,
        state: state,
        isFavorite: isFavorite,
        onRefresh: _refresh,
        navTitle: widget.navTitle,
        inheritedSeries: widget.inferredSeries,
      ),
    );
  }
}

class _BrowseContent extends ConsumerWidget {
  final BrowseArgs args;
  final BrowseState state;
  final bool isFavorite;
  final Future<void> Function() onRefresh;
  final String? navTitle;
  final String? inheritedSeries;

  const _BrowseContent({
    required this.args,
    required this.state,
    required this.isFavorite,
    required this.onRefresh,
    this.navTitle,
    this.inheritedSeries,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (catalogId, url) = args;
    final entries = state.feed.feed.entries;
    final jobState = ref.watch(folderDownloadProvider);
    final inferredSeries = inferSeriesFromUrl(url) ?? inheritedSeries;

    ref.listen(lastDownloadResultProvider, (_, result) {
      if (result == null) return;
      ref.read(lastDownloadResultProvider.notifier).clear();
      final msg = result.alreadyExisted
          ? 'Already downloaded: ${result.fileName}'
          : 'Downloaded: ${result.fileName}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          showCloseIcon: true,
          action: result.alreadyExisted
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => openFile(result.contentUri, result.mimeType),
                ),
        ),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.feed.feed.title),
            Text(
              formatRelativeTime(state.feed.fetchedAt, DateTime.now()),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.isRefreshing ? null : () => onRefresh(),
          ),
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            onPressed: () => ref
                .read(favoritesProvider.notifier)
                .toggle(catalogId, url, navTitle ?? state.feed.feed.title),
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Download folder',
            onPressed: jobState is FolderJobIdle
                ? () => context.push(
                    '/folder-scan?catalogId=$catalogId&url=${Uri.encodeComponent(url.toString())}',
                  )
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (kDebugMode)
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: SelectableText(
                '$url\nseries: $inferredSeries',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          if (state.isRefreshing) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (entries.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: Text('This folder is empty.')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = entries[index];
                        return switch (entry) {
                          NavigationEntry e => _NavigationEntryTile(
                            entry: e,
                            catalogId: catalogId,
                            inferredSeries: inferredSeries,
                            key: ValueKey(e.url),
                          ),
                          BookEntry e => _BookEntryTile(
                            entry: e,
                            inferredSeries: inferredSeries,
                            key: ValueKey(e.title),
                          ),
                        };
                      }, childCount: entries.length),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSeriesIndex(double idx) =>
    idx == idx.truncateToDouble() ? idx.toInt().toString() : idx.toString();

class _NavigationEntryTile extends StatelessWidget {
  final NavigationEntry entry;
  final int catalogId;
  final String? inferredSeries;

  const _NavigationEntryTile({
    required this.entry,
    required this.catalogId,
    this.inferredSeries,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final seriesParam = inferredSeries != null
        ? '&series=${Uri.encodeComponent(inferredSeries!)}'
        : '';
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(entry.title),
      subtitle: entry.subtitle != null
          ? Text(entry.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () => context.push(
        '/browse?catalogId=$catalogId&url=${Uri.encodeComponent(entry.url.toString())}&title=${Uri.encodeComponent(entry.title)}$seriesParam',
      ),
    );
  }
}

class _BookEntryTile extends ConsumerStatefulWidget {
  final BookEntry entry;
  final String? inferredSeries;

  const _BookEntryTile({required this.entry, this.inferredSeries, super.key});

  @override
  ConsumerState<_BookEntryTile> createState() => _BookEntryTileState();
}

class _BookEntryTileState extends ConsumerState<_BookEntryTile> {
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
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => BookDetailsSheet(entry: entry),
      ),
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
          Text(
            seriesText ?? '',
            style: isInferredSeries
                ? const TextStyle(fontStyle: FontStyle.italic)
                : null,
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
                    onPressed: () => _onDownloadTap(context),
                  )
          : null,
    );
  }

  Future<void> _onDownloadTap(BuildContext context) async {
    final entry = widget.entry;
    final settings =
        ref.read(settingsProvider).value ??
        const AppSettings(target: SystemDownloads());
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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/time_formatter.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/widgets/folder_job_banner.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  final int catalogId;
  final Uri url;

  const BrowseScreen({required this.catalogId, required this.url, super.key});

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
      ),
    );
  }
}

class _BrowseContent extends ConsumerWidget {
  final BrowseArgs args;
  final BrowseState state;
  final bool isFavorite;
  final Future<void> Function() onRefresh;

  const _BrowseContent({
    required this.args,
    required this.state,
    required this.isFavorite,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (catalogId, url) = args;
    final entries = state.feed.feed.entries;
    final jobState = ref.watch(folderDownloadProvider);

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
                  onPressed: () => OpenFilex.open(result.contentUri),
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
                .toggle(catalogId, url, state.feed.feed.title),
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Download folder',
            onPressed: (jobState is FolderJobIdle || jobState is FolderJobDone)
                ? () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Download folder'),
                        content: const Text(
                          'Download all books in this folder and its '
                          'subfolders? This may be a large amount of data.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('DOWNLOAD'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      ref
                          .read(folderDownloadProvider.notifier)
                          .start(catalogId, url);
                    }
                  }
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
                url.toString(),
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
                            key: ValueKey(e.url),
                          ),
                          BookEntry e => _BookEntryTile(
                            entry: e,
                            key: ValueKey(e.title),
                          ),
                        };
                      }, childCount: entries.length),
                    ),
                ],
              ),
            ),
          ),
          const FolderJobBanner(),
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

  const _NavigationEntryTile({
    required this.entry,
    required this.catalogId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(entry.title),
      subtitle: entry.subtitle != null
          ? Text(entry.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () => context.push(
        '/browse?catalogId=$catalogId&url=${Uri.encodeComponent(entry.url.toString())}',
      ),
    );
  }
}

class _BookEntryTile extends StatelessWidget {
  final BookEntry entry;

  const _BookEntryTile({required this.entry, super.key});

  @override
  Widget build(BuildContext context) {
    final authors = entry.authors.join(', ');
    final seriesText = entry.series != null
        ? (entry.seriesIndex != null
              ? '${entry.series} #${_formatSeriesIndex(entry.seriesIndex!)}'
              : entry.series!)
        : null;
    final hasSubtitle = authors.isNotEmpty || seriesText != null;

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
      subtitle: hasSubtitle
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (authors.isNotEmpty) Text(authors),
                if (seriesText != null) Text(seriesText),
              ],
            )
          : null,
      isThreeLine: authors.isNotEmpty && seriesText != null,
    );
  }
}

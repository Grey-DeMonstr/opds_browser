import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/browse_list.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_search.dart';
import 'package:opds_browser/domain/url_debug_formatter.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/ui/book_details_sheet.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/require_library_folder.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/filter_chip_bar.dart';

/// Horizontal inset shared by the header, the chips and every row.
const _gutter = 16.0;

class BrowseScreen extends ConsumerStatefulWidget {
  final int catalogId;
  final Uri url;
  final String? navTitle;
  final String? navSubtitle;
  final String? inferredSeries;

  const BrowseScreen({
    required this.catalogId,
    required this.url,
    this.navTitle,
    this.navSubtitle,
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
        navSubtitle: widget.navSubtitle,
        inheritedSeries: widget.inferredSeries,
      ),
    );
  }
}

class _BrowseContent extends ConsumerStatefulWidget {
  final BrowseArgs args;
  final BrowseState state;
  final bool isFavorite;
  final Future<void> Function() onRefresh;
  final String? navTitle;
  final String? navSubtitle;
  final String? inheritedSeries;

  const _BrowseContent({
    required this.args,
    required this.state,
    required this.isFavorite,
    required this.onRefresh,
    this.navTitle,
    this.navSubtitle,
    this.inheritedSeries,
  });

  @override
  ConsumerState<_BrowseContent> createState() => _BrowseContentState();
}

class _BrowseContentState extends ConsumerState<_BrowseContent> {
  bool _bucketsHidden = false;
  bool _filterOpen = false;
  String _query = '';
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _toggleFilter() {
    setState(() {
      _filterOpen = !_filterOpen;
      if (!_filterOpen) {
        _query = '';
        _filterController.clear();
      }
    });
  }

  /// Where this folder was reached from — the entry that was tapped, and what
  /// it said was inside. Absent at the root of a catalogue.
  String? get _contextLine {
    final title = widget.navTitle;
    if (title == null || title.isEmpty) return null;
    final subtitle = widget.navSubtitle;
    return subtitle == null || subtitle.isEmpty ? title : '$title · $subtitle';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (catalogId, url) = widget.args;
    final state = widget.state;
    final entries = state.feed.feed.entries;
    final jobState = ref.watch(folderDownloadProvider);
    final debugMode = ref.watch(
      settingsProvider.select((s) => s.value?.debugMode ?? false),
    );
    final inferredSeries = inferSeriesFromUrl(url) ?? widget.inheritedSeries;
    // Counted over everything the catalogue sent, before All / Entries only
    // narrows it, so the chip does not appear and vanish as those are
    // switched. A shorter page is readable as it stands and the chip would
    // only be noise.
    // The Search row belongs to the catalogue root and nowhere else.
    // Catalogues repeat rel="search" on every feed they serve, so the link
    // alone would put the row on every level; only the root is asked.
    final catalog = ref.watch(catalogByIdProvider(catalogId));
    final atRoot =
        catalog != null && normalizeUrl(catalog.rootUrl) == normalizeUrl(url);
    final searchable =
        atRoot && preferredSearchLink(state.feed.feed.searchLinks) != null;

    final filterAvailable = entries.length > _filterMinRows;
    final filterOpen = _filterOpen && filterAvailable;
    final visible = filterBrowseEntries(
      entries,
      bucketsHidden: _bucketsHidden,
      query: filterOpen ? _query : '',
    );
    final contextLine = _contextLine;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.feed.feed.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                height: 1.2,
                letterSpacing: -0.2,
                color: scheme.onSurface,
              ),
            ),
            if (contextLine != null)
              Text(
                contextLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: 19,
            onPressed: state.isRefreshing ? null : () => widget.onRefresh(),
          ),
          IconButton(
            icon: Icon(
              widget.isFavorite ? Icons.star : Icons.star_border,
              color: widget.isFavorite ? scheme.primary : null,
            ),
            iconSize: 19,
            onPressed: () => ref
                .read(favoritesProvider.notifier)
                .toggle(
                  catalogId,
                  url,
                  widget.navTitle ?? state.feed.feed.title,
                ),
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            iconSize: 19,
            tooltip: 'Download folder',
            onPressed: jobState is FolderJobIdle
                ? () async {
                    if (!await ensureLibraryFolder(context, ref)) return;
                    if (!context.mounted) return;
                    context.push(
                      '/folder-scan?catalogId=$catalogId&url=${Uri.encodeComponent(url.toString())}',
                    );
                  }
                : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (debugMode) _DebugUrlPanel(url: url),
            if (state.isRefreshing) const LinearProgressIndicator(),
            _FilterBar(
              bucketsHidden: _bucketsHidden,
              filterAvailable: filterAvailable,
              filterOpen: filterOpen,
              onShowAll: () => setState(() => _bucketsHidden = false),
              onHideBuckets: () => setState(() => _bucketsHidden = true),
              onToggleFilter: _toggleFilter,
            ),
            if (filterOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10),
                child: TextField(
                  controller: _filterController,
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Filter this page',
                    prefixIcon: Icon(Icons.filter_alt_outlined, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            const FadingRule(margin: EdgeInsets.symmetric(horizontal: _gutter)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (searchable)
                      SliverToBoxAdapter(
                        child: _SearchRow(
                          catalogId: catalogId,
                          rootUrl: catalog.rootUrl,
                        ),
                      ),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Text(
                            entries.isEmpty
                                ? 'This folder is empty.'
                                : 'Nothing on this page matches.',
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final entry = visible[index];
                          return switch (entry) {
                            NavigationEntry e => NavigationEntryRow(
                              entry: e,
                              catalogId: catalogId,
                              inferredSeries: inferredSeries,
                              key: ValueKey(e.url),
                            ),
                            BookEntry e => BookEntryTile(
                              entry: e,
                              inferredSeries: inferredSeries,
                              key: ValueKey(e.title),
                            ),
                          };
                        }, childCount: visible.length),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The debug panel: the current URL, decoded and one query parameter per line.
/// Tapping it puts the full URL on the clipboard.
class _DebugUrlPanel extends StatelessWidget {
  final Uri url;

  const _DebugUrlPanel({required this.url});

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url.toString()));
    messenger.showSnackBar(const SnackBar(content: Text('URL copied')));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _copy(context),
      child: Container(
        width: double.infinity,
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          formatUrlForDebug(url),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'monospace',
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// The catalogue root's first row: the way into a catalogue-wide search.
///
/// It takes the same shape as the folders beneath it, because that is what it
/// is — one more way into the catalogue — and it is accented to mark it as the
/// one row that is not a folder the catalogue published. The subtitle carries
/// the caveat, since a search really can take a while.
class _SearchRow extends StatelessWidget {
  final int catalogId;
  final Uri rootUrl;

  const _SearchRow({required this.catalogId, required this.rootUrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return InkWell(
      onTap: () => context.push(
        '/search?catalogId=$catalogId'
        '&rootUrl=${Uri.encodeComponent(rootUrl.toString())}',
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: _gutter, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 19, color: scheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Search',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: scheme.primary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Every book in the catalogue · slow',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The number of rows a page must exceed before the filter is offered.
const _filterMinRows = 5;

/// The chips that narrow the list: everything, entries only, or a name filter.
///
/// The filter is a filter and not a search: it narrows the rows already on
/// screen and never asks the catalogue anything.
class _FilterBar extends StatelessWidget {
  final bool bucketsHidden;
  final bool filterAvailable;
  final bool filterOpen;
  final VoidCallback onShowAll;
  final VoidCallback onHideBuckets;
  final VoidCallback onToggleFilter;

  const _FilterBar({
    required this.bucketsHidden,
    required this.filterAvailable,
    required this.filterOpen,
    required this.onShowAll,
    required this.onHideBuckets,
    required this.onToggleFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10),
      child: Row(
        children: [
          NocturneChip(
            label: 'All',
            selected: !bucketsHidden,
            onTap: onShowAll,
          ),
          const SizedBox(width: 7),
          NocturneChip(
            label: 'Entries only',
            selected: bucketsHidden,
            onTap: onHideBuckets,
          ),
          if (filterAvailable) ...[
            const SizedBox(width: 7),
            NocturneChip(
              label: 'Filter',
              icon: Icons.filter_alt_outlined,
              selected: filterOpen,
              onTap: onToggleFilter,
            ),
          ],
        ],
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: _gutter, vertical: 13),
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

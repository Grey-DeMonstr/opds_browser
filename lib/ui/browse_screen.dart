import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/data/folder_download_job.dart';
import 'package:opds_browser/data/url_normalizer.dart';
import 'package:opds_browser/domain/browse_list.dart';
import 'package:opds_browser/domain/catalog_url_formatter.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entry_icon.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_search.dart';
import 'package:opds_browser/domain/url_debug_formatter.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/require_library_folder.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/entry_rows.dart';
import 'package:opds_browser/ui/widgets/filter_chip_bar.dart';

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
  /// it said was inside. Absent at the root of a catalogue, which names its
  /// own URL instead.
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
            if (atRoot)
              Text(
                formatCatalogUrl(catalog.rootUrl),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else if (contextLine != null)
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
            if (filterAvailable)
              _FilterBar(
                bucketsHidden: _bucketsHidden,
                filterOpen: filterOpen,
                onShowAll: () => setState(() => _bucketsHidden = false),
                onHideBuckets: () => setState(() => _bucketsHidden = true),
                onToggleFilter: _toggleFilter,
              ),
            if (filterOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 10),
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
            const FadingRule(margin: EdgeInsets.symmetric(horizontal: gutter)),
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
                            NavigationEntry e when atRoot => _RootSectionRow(
                              entry: e,
                              catalogId: catalogId,
                              key: ValueKey(e.url),
                            ),
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

/// The tile that carries a root row's glyph.
///
/// The root reads as a short list of ways into the catalogue rather than a
/// feed of entries, so its rows are marked the way the home screen marks a
/// catalogue: one square, one glyph, the title and its count beside it.
class _RootMark extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;

  const _RootMark({
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: border),
    ),
    child: Icon(icon, size: 18, color: foreground),
  );
}

/// The shared shape of a root row: mark, title, subtitle, caret.
class _RootRow extends StatelessWidget {
  final Widget mark;
  final String title;
  final String? subtitle;
  final Color titleColor;
  final Color caretColor;
  final Color? background;
  final VoidCallback onTap;

  const _RootRow({
    required this.mark,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.caretColor,
    required this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 13),
        child: Row(
          children: [
            mark,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.3,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: caretColor),
          ],
        ),
      ),
    );
  }
}

/// One of the ways into a catalogue, as its root lists them.
class _RootSectionRow extends StatelessWidget {
  final NavigationEntry entry;
  final int catalogId;

  const _RootSectionRow({
    required this.entry,
    required this.catalogId,
    super.key,
  });

  static const _icons = {
    EntryGlyph.author: Icons.person_outline,
    EntryGlyph.series: Icons.layers_outlined,
    EntryGlyph.title: Icons.menu_book_outlined,
    EntryGlyph.genre: Icons.sell_outlined,
    EntryGlyph.popular: Icons.trending_up,
    EntryGlyph.newest: Icons.history,
    EntryGlyph.random: Icons.shuffle,
    EntryGlyph.folder: Icons.folder_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final subtitleParam = entry.subtitle != null
        ? '&subtitle=${Uri.encodeComponent(entry.subtitle!)}'
        : '';

    return _RootRow(
      mark: _RootMark(
        icon: _icons[glyphForEntryUrl(entry.url)]!,
        background: palette.catalogMarkSurface,
        border: scheme.outlineVariant,
        foreground: scheme.primary,
      ),
      title: entry.title,
      subtitle: entry.subtitle,
      titleColor: scheme.onSurface,
      caretColor: palette.dim,
      onTap: () => context.push(
        '/browse?catalogId=$catalogId'
        '&url=${Uri.encodeComponent(entry.url.toString())}'
        '&title=${Uri.encodeComponent(entry.title)}$subtitleParam',
      ),
    );
  }
}

/// The catalogue root's first row: the way into a catalogue-wide search.
///
/// It takes the same shape as the sections beneath it, because that is what it
/// is — one more way into the catalogue — and it is accented to mark it as the
/// one row the catalogue did not itself publish.
class _SearchRow extends StatelessWidget {
  final int catalogId;
  final Uri rootUrl;

  const _SearchRow({required this.catalogId, required this.rootUrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Column(
      children: [
        _RootRow(
          mark: _RootMark(
            icon: Icons.search,
            background: palette.accentFill,
            border: palette.accentStrong,
            foreground: scheme.primary,
          ),
          title: 'Search',
          subtitle: null,
          titleColor: scheme.primary,
          caretColor: scheme.primary,
          background: scheme.primary.withValues(alpha: 0.06),
          onTap: () => context.push(
            '/search?catalogId=$catalogId'
            '&rootUrl=${Uri.encodeComponent(rootUrl.toString())}',
          ),
        ),
        // Sets the one row that is not a published section apart from them,
        // fading out rather than ruling all the way across.
        Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(gutter, 6, gutter, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.accentStrong,
                palette.accentStrong.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The number of rows a page must exceed before the filter is offered.
const _filterMinRows = 5;

/// The chips that narrow the list: everything, entries only, or a name filter.
///
/// The filter is a filter and not a search: it narrows the rows already on
/// screen and never asks the catalogue anything.
///
/// Whether the bar appears at all is the caller's decision, and it is the same
/// question as whether the filter is worth offering — a page short enough to
/// read whole has no use for any of these.
class _FilterBar extends StatelessWidget {
  final bool bucketsHidden;
  final bool filterOpen;
  final VoidCallback onShowAll;
  final VoidCallback onHideBuckets;
  final VoidCallback onToggleFilter;

  const _FilterBar({
    required this.bucketsHidden,
    required this.filterOpen,
    required this.onShowAll,
    required this.onHideBuckets,
    required this.onToggleFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 10),
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
          const SizedBox(width: 7),
          NocturneChip(
            label: 'Filter',
            icon: Icons.filter_alt_outlined,
            selected: filterOpen,
            onTap: onToggleFilter,
          ),
        ],
      ),
    );
  }
}

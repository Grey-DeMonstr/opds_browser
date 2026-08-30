import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/entry_rows.dart';
import 'package:opds_browser/ui/widgets/filter_chip_bar.dart';

/// One catalogue-wide query and its results.
///
/// The screen exists to set the expectations the protocol forces on us: the
/// scope is the whole catalogue rather than the folder the reader came from,
/// results arrive a page at a time, and there is no total to count towards.
class SearchScreen extends ConsumerStatefulWidget {
  final int catalogId;
  final Uri rootUrl;

  const SearchScreen({
    required this.catalogId,
    required this.rootUrl,
    super.key,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  /// True while the query field is showing, whatever results are held behind
  /// it. The design puts the query in the app bar once results arrive; this is
  /// what lets the reader get back to the field to ask something else.
  bool _editing = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SearchArgs get _args => (widget.catalogId, widget.rootUrl);

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    setState(() => _editing = false);
    ref.read(searchProvider(_args).notifier).search(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(searchProvider(_args));
    final catalog = ref
        .watch(catalogsProvider)
        .value
        ?.where((c) => c.id == widget.catalogId)
        .firstOrNull;
    final catalogTitle = catalog?.title ?? 'this catalogue';
    final showField = _editing || state.status == SearchStatus.idle;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: showField
            ? Text(
                'Search',
                style: TextStyle(fontSize: 20, color: scheme.onSurface),
              )
            : _QueryTitle(
                query: state.query,
                meta: _metaLine(catalogTitle, state),
              ),
        actions: [
          if (!showField)
            IconButton(
              icon: const Icon(Icons.search),
              iconSize: 19,
              tooltip: 'New search',
              onPressed: () => setState(() {
                _editing = true;
                _controller.text = state.query;
              }),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: showField
            ? _QueryForm(
                controller: _controller,
                catalogTitle: catalogTitle,
                onSubmit: _submit,
              )
            : _Results(
                state: state,
                catalogId: widget.catalogId,
                onStop: () => ref.read(searchProvider(_args).notifier).stop(),
                onContinue: () =>
                    ref.read(searchProvider(_args).notifier).resume(),
                onRetry: () => ref
                    .read(searchProvider(_args).notifier)
                    .search(state.query),
              ),
      ),
    );
  }

  /// What the header says about progress. The count is what has arrived, not
  /// a total — the protocol never sends one.
  String _metaLine(String catalogTitle, SearchState state) {
    if (state.status == SearchStatus.failed) return catalogTitle;
    final pages = state.pagesLoaded;
    return '$catalogTitle · ${state.entries.length} loaded · page $pages';
  }
}

class _QueryTitle extends StatelessWidget {
  final String query;
  final String meta;

  const _QueryTitle({required this.query, required this.meta});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          query,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            height: 1.2,
            letterSpacing: -0.2,
            color: scheme.onSurface,
          ),
        ),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The field, and the one honest caveat about what a search costs.
class _QueryForm extends StatelessWidget {
  final TextEditingController controller;
  final String catalogTitle;
  final void Function(String) onSubmit;

  const _QueryForm({
    required this.controller,
    required this.catalogTitle,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 14, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmit,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Title, author or series',
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Searches all of $catalogTitle, and results arrive '
              'one page at a time and can take a while.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final SearchState state;
  final int catalogId;
  final VoidCallback onStop;
  final VoidCallback onContinue;
  final VoidCallback onRetry;

  const _Results({
    required this.state,
    required this.catalogId,
    required this.onStop,
    required this.onContinue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final empty =
        state.entries.isEmpty &&
        (state.status == SearchStatus.done ||
            state.status == SearchStatus.stopped);

    return Column(
      children: [
        const FadingRule(margin: EdgeInsets.symmetric(horizontal: gutter)),
        Expanded(
          child: empty
              ? const Center(child: Text('Nothing found for that.'))
              : ListView.builder(
                  itemCount: state.entries.length,
                  itemBuilder: (context, index) {
                    final entry = state.entries[index];
                    // A result feed carries whichever kind the catalogue
                    // chose: books from most, a menu of scopes from some.
                    return switch (entry) {
                      NavigationEntry e => NavigationEntryRow(
                        entry: e,
                        catalogId: catalogId,
                        key: ValueKey(e.url),
                      ),
                      BookEntry e => BookEntryTile(
                        entry: e,
                        key: ValueKey('${e.title}#$index'),
                      ),
                    };
                  },
                ),
        ),
        _Footer(
          state: state,
          onStop: onStop,
          onContinue: onContinue,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

/// What the walk is doing, and the one control over it.
///
/// Absent once a result set is complete: a catalogue that answered in one
/// unpaginated page has nothing left to say, and a footer offering Continue
/// there would promise a page that does not exist.
class _Footer extends StatelessWidget {
  final SearchState state;
  final VoidCallback onStop;
  final VoidCallback onContinue;
  final VoidCallback onRetry;

  const _Footer({
    required this.state,
    required this.onStop,
    required this.onContinue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    final (
      String? line,
      String? action,
      VoidCallback? onAction,
    ) = switch (state.status) {
      SearchStatus.running => (
        'Fetching page ${state.pagesLoaded + 1}…',
        'Stop',
        onStop,
      ),
      SearchStatus.stopped when state.nextPageUrl != null => (
        'Stopped at page ${state.pagesLoaded} of an unknown total',
        'Continue',
        onContinue,
      ),
      SearchStatus.failed => (state.error, 'Retry', onRetry),
      _ => (null, null, null),
    };
    if (line == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(gutter, 10, gutter, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        children: [
          if (state.status == SearchStatus.running)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          Expanded(
            child: Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

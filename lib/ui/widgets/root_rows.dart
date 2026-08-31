/// The rows a catalogue's root is drawn from.
///
/// The root reads as a short list of ways into the catalogue rather than a
/// feed of entries, so it is set the way the home screen sets a catalogue —
/// one square, one glyph, the title and its count beside it — and not the way
/// the levels beneath it are set. Every level below the root draws
/// `NavigationEntryRow` instead.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:opds_browser/domain/entry_icon.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/filter_chip_bar.dart';
import 'package:opds_browser/ui/widgets/mark_row.dart';

/// The metrics every root row shares, on the browse screen's inset.
const _rowPadding = EdgeInsets.symmetric(horizontal: gutter, vertical: 13);
const _rowGap = 13.0;

/// The glyph a root section is marked with.
///
/// A switch rather than a map, so that adding an [EntryGlyph] is a compile
/// error here instead of a null at the moment the row is drawn.
IconData _iconFor(EntryGlyph glyph) => switch (glyph) {
  EntryGlyph.author => Icons.person_outline,
  EntryGlyph.series => Icons.layers_outlined,
  EntryGlyph.title => Icons.menu_book_outlined,
  EntryGlyph.genre => Icons.sell_outlined,
  EntryGlyph.popular => Icons.trending_up,
  EntryGlyph.newest => Icons.history,
  EntryGlyph.random => Icons.shuffle,
  EntryGlyph.folder => Icons.folder_outlined,
};

/// The quieter line under a root section's title — what the catalogue said is
/// inside it. Absent when the catalogue said nothing.
class _Subtitle extends StatelessWidget {
  final String? text;

  const _Subtitle(this.text);

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One of the ways into a catalogue, as its root lists them.
class RootSectionRow extends StatelessWidget {
  final NavigationEntry entry;
  final int catalogId;

  const RootSectionRow({
    required this.entry,
    required this.catalogId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final subtitleParam = entry.subtitle != null
        ? '&subtitle=${Uri.encodeComponent(entry.subtitle!)}'
        : '';

    return MarkRow(
      mark: Mark(
        background: palette.catalogMarkSurface,
        border: scheme.outlineVariant,
        child: Icon(
          _iconFor(glyphForEntryUrl(entry.url)),
          size: 18,
          color: scheme.primary,
        ),
      ),
      title: entry.title,
      subtitle: _Subtitle(entry.subtitle),
      padding: _rowPadding,
      gap: _rowGap,
      trailing: Icon(Icons.chevron_right, size: 18, color: palette.dim),
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
class RootSearchRow extends StatelessWidget {
  final int catalogId;
  final Uri rootUrl;

  const RootSearchRow({
    required this.catalogId,
    required this.rootUrl,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Column(
      children: [
        MarkRow(
          mark: Mark(
            background: palette.accentFill,
            border: palette.accentStrong,
            child: Icon(Icons.search, size: 18, color: scheme.primary),
          ),
          title: 'Search',
          titleColor: scheme.primary,
          padding: _rowPadding,
          gap: _rowGap,
          trailing: Icon(Icons.chevron_right, size: 18, color: scheme.primary),
          background: scheme.primary.withValues(alpha: 0.06),
          onTap: () => context.push(
            '/search?catalogId=$catalogId'
            '&rootUrl=${Uri.encodeComponent(rootUrl.toString())}',
          ),
        ),
        // Sets the one row that is not a published section apart from them,
        // fading out rather than ruling all the way across, and accented
        // rather than drawn at the palette's own rule weight.
        FadingRule(
          margin: const EdgeInsets.fromLTRB(gutter, 6, gutter, 6),
          color: palette.accentStrong,
          fade: RuleFade.trailing,
        ),
      ],
    );
  }
}

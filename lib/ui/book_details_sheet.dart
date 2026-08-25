import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opds_browser/domain/book_content.dart';
import 'package:opds_browser/domain/download_utils.dart';
import 'package:opds_browser/domain/entities.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/ui/providers.dart';
import 'package:opds_browser/ui/theme.dart';

/// Presents [BookDetailsSheet] as a draggable panel that can grow to the full
/// screen. Descriptions vary wildly in length between catalogues — Project
/// Gutenberg packs a whole bibliographic record into one — so the panel scrolls
/// rather than truncating, and the actions below stay reachable.
Future<void> showBookDetailsSheet(BuildContext context, BookEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BookDetailsSheet(entry: entry),
  );
}

/// Lines of the description shown before Show more, when the markup gave us no
/// headings to split on.
const _clampedLines = 6;

class BookDetailsSheet extends ConsumerStatefulWidget {
  const BookDetailsSheet({required this.entry, super.key});

  final BookEntry entry;

  @override
  ConsumerState<BookDetailsSheet> createState() => _BookDetailsSheetState();
}

class _BookDetailsSheetState extends ConsumerState<BookDetailsSheet> {
  Uri? _activeDownloadUrl;
  bool _detailsOpen = false;
  bool _blurbExpanded = false;

  /// Parsed once per sheet rather than per rebuild — splitting a full FB2
  /// bibliographic record is not free, and nothing about it changes while the
  /// sheet is open.
  late final BookContent? _content = widget.entry.contentHtml == null
      ? null
      : parseBookContent(widget.entry.contentHtml!);

  /// The format the button fetches: first by preference, never null while the
  /// entry has links at all.
  AcquisitionLink? get _primaryLink => widget.entry.acquisitionLinks.isEmpty
      ? null
      : folderPreferredLink(widget.entry.acquisitionLinks);

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final primary = _primaryLink;

    DownloadState? downloadState;
    if (primary != null) {
      final watchUrl = _activeDownloadUrl ?? primary.url;
      downloadState = ref.watch(downloadNotifierProvider(watchUrl));
      ref.listen(downloadNotifierProvider(watchUrl), (_, state) {
        if (state is DownloadFailed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: ${state.message}'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => ref
                    .read(downloadNotifierProvider(watchUrl).notifier)
                    .start(entry, settings),
              ),
            ),
          );
        }
      });
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(entry: entry),
            if (primary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: _Formats(
                  primary: primary,
                  others: entry.acquisitionLinks
                      .where((l) => l != primary)
                      .toList(),
                  downloading: downloadState is DownloadInProgress,
                  onDownload: _startDownload,
                ),
              ),
            const _FadingRule(),
            ..._buildContent(context),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _startDownload(AcquisitionLink link) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    setState(() => _activeDownloadUrl = link.url);
    ref
        .read(downloadNotifierProvider(link.url).notifier)
        .start(widget.entry, settings);
  }

  /// Rule 1 — headings present: the blurb whole, the facts behind Details.
  /// Rule 2 — no headings: the text clamped, with Show more, and no Details.
  List<Widget> _buildContent(BuildContext context) {
    final content = _content;

    if (content == null) {
      final summary = widget.entry.summary;
      if (summary == null) return const [];
      return [
        _ClampedBlurb(
          text: summary,
          expanded: _blurbExpanded,
          onToggle: _toggleBlurb,
        ),
      ];
    }

    if (!content.hasDetails) {
      final text = content.blurbText;
      if (text.isEmpty) return const [];
      return [
        _ClampedBlurb(
          text: text,
          expanded: _blurbExpanded,
          onToggle: _toggleBlurb,
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final block in content.blurb) _BlockView(block: block),
          ],
        ),
      ),
      _DetailsDisclosure(
        open: _detailsOpen,
        onToggle: () => setState(() => _detailsOpen = !_detailsOpen),
        sections: content.details,
      ),
    ];
  }

  void _toggleBlurb() => setState(() => _blurbExpanded = !_blurbExpanded);
}

/// Cover, title, byline, tags — all of it straight from Atom fields.
class _Header extends StatelessWidget {
  const _Header({required this.entry});

  final BookEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            height: 126,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.cardSurface,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              child: entry.coverUrl != null
                  ? ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                      child: CachedNetworkImage(
                        imageUrl: entry.coverUrl!.toString(),
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Icon(Icons.book_outlined, color: palette.dim),
                        errorWidget: (_, _, _) =>
                            Icon(Icons.book_outlined, color: palette.dim),
                      ),
                    )
                  : Icon(Icons.book_outlined, color: palette.dim),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  style: TextStyle(
                    fontSize: 18.5,
                    height: 1.25,
                    letterSpacing: -0.2,
                    color: scheme.onSurface,
                  ),
                ),
                if (entry.authors.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    entry.authors.join(', '),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                // Not in turn 4's field list, but the old page showed it and
                // Calibre feeds carry it in `calibre:series`, where no amount
                // of content parsing would find it.
                if (entry.series != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _seriesText(entry),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: appPaletteOf(context).dim,
                    ),
                  ),
                ],
                if (entry.categories.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Wrap(
                    key: const Key('book-tags'),
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in entry.categories)
                        _Tag(label: category),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _seriesText(BookEntry entry) {
  final index = entry.seriesIndex;
  if (index == null) return entry.series!;
  final label = index == index.truncateToDouble()
      ? index.toInt().toString()
      : index.toString();
  return '${entry.series} #$label';
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accentFill,
        border: Border.all(color: palette.accentStrong),
        borderRadius: const BorderRadius.all(Radius.circular(5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, height: 1.2, color: scheme.primary),
      ),
    );
  }
}

/// The one named action, and the other formats beside it as chips.
class _Formats extends StatelessWidget {
  const _Formats({
    required this.primary,
    required this.others,
    required this.downloading,
    required this.onDownload,
  });

  final AcquisitionLink primary;
  final List<AcquisitionLink> others;
  final bool downloading;
  final void Function(AcquisitionLink) onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (downloading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onDownload(primary),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: BorderSide(color: palette.accentStrong),
                backgroundColor: palette.accentFill,
                foregroundColor: scheme.primary,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              child: Text(
                'Download ${primary.formatLabel}',
                style: const TextStyle(fontSize: 14.5, height: 1.2),
              ),
            ),
          ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('or', style: TextStyle(fontSize: 11, color: palette.dim)),
                for (final link in others)
                  _FormatChip(
                    link: link,
                    onTap: downloading ? null : () => onDownload(link),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.link, required this.onTap});

  final AcquisitionLink link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(7)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: const BorderRadius.all(Radius.circular(7)),
        ),
        child: Text(
          link.formatLabel,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The Nocturne rule: a hairline that fades out at both ends.
class _FadingRule extends StatelessWidget {
  const _FadingRule();

  @override
  Widget build(BuildContext context) {
    final line = appPaletteOf(context).hairline;

    return Container(
      height: 1,
      margin: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          stops: const [0, 0.15, 0.85, 1],
          colors: [
            line.withValues(alpha: 0),
            line,
            line,
            line.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// Rule 2's presentation: the description as one flowing block, six lines until
/// asked for more.
class _ClampedBlurb extends StatelessWidget {
  const _ClampedBlurb({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            key: const Key('book-blurb'),
            maxLines: expanded ? null : _clampedLines,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.62,
              color: scheme.onSurfaceVariant,
            ),
          ),
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                expanded ? 'Show less' : 'Show more',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rule 1's presentation: everything from the first heading down, collapsed.
class _DetailsDisclosure extends StatelessWidget {
  const _DetailsDisclosure({
    required this.open,
    required this.onToggle,
    required this.sections,
  });

  final bool open;
  final VoidCallback onToggle;
  final List<DetailSection> sections;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            margin: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: scheme.primary,
                    ),
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final section in sections) _SectionView(section: section),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final DetailSection section;

  @override
  Widget build(BuildContext context) {
    final palette = appPaletteOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(
            section.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.4,
              color: palette.dim,
            ),
          ),
        ),
        for (final row in section.rows) _FactRow(row: row),
        for (final note in section.notes) _BlockView(block: note),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.row});

  final DetailRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// One parsed content block — a paragraph or a list — as text.
class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 13.5,
      height: 1.62,
      color: scheme.onSurfaceVariant,
    );

    return switch (block) {
      ContentParagraph(:final spans) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text.rich(
          TextSpan(children: _spansOf(spans, style)),
          style: style,
        ),
      ),
      ContentBullet(:final items, :final ordered) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, item) in items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: ordered ? '${index + 1}. ' : '•  '),
                      ..._spansOf(item, style),
                    ],
                  ),
                  style: style,
                ),
              ),
          ],
        ),
      ),
    };
  }

  List<InlineSpan> _spansOf(List<ContentSpan> spans, TextStyle base) => [
    for (final span in spans)
      TextSpan(
        text: span.text,
        style: base.copyWith(
          fontWeight: span.bold ? FontWeight.w600 : null,
          fontStyle: span.italic ? FontStyle.italic : null,
        ),
      ),
  ];
}

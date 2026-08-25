import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// A run of text inside a paragraph, carrying whatever emphasis survived
/// sanitising.
class ContentSpan {
  final String text;
  final bool bold;
  final bool italic;

  /// Left as the feed wrote it — hrefs in the wild are relative, or carry an
  /// FB2 `l:` prefix, and the UI decides what is worth linking.
  final String? href;

  const ContentSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.href,
  });
}

sealed class ContentBlock {
  const ContentBlock();
}

class ContentParagraph extends ContentBlock {
  final List<ContentSpan> spans;
  const ContentParagraph(this.spans);

  String get text => spans.map((s) => s.text).join();
}

class ContentBullet extends ContentBlock {
  final bool ordered;
  final List<List<ContentSpan>> items;
  const ContentBullet({required this.ordered, required this.items});
}

/// One `key: value` fact under a heading.
class DetailRow {
  final String label;
  final String value;
  const DetailRow(this.label, this.value);
}

/// A heading and everything under it, up to the next heading.
class DetailSection {
  final String label;

  /// 1–6, from `h1`–`h6`.
  final int level;
  final List<DetailRow> rows;

  /// Content under the heading that is not a `key: value` fact.
  final List<ContentBlock> notes;

  const DetailSection({
    required this.label,
    required this.level,
    required this.rows,
    required this.notes,
  });
}

/// An entry's description, split the way the book page presents it.
class BookContent {
  /// Everything before the first heading.
  final List<ContentBlock> blurb;

  /// One entry per heading, in document order. Empty when the markup has no
  /// headings at all — that is the whole of rule 2.
  final List<DetailSection> details;

  const BookContent({required this.blurb, required this.details});

  bool get hasDetails => details.isNotEmpty;

  /// The blurb as one flowing string, paragraphs separated by a blank line.
  String get blurbText =>
      blurb.whereType<ContentParagraph>().map((p) => p.text).join('\n\n');
}

/// Inline elements whose emphasis we keep; everything else inline is unwrapped.
const _bold = {'b', 'strong'};
const _italic = {'i', 'em'};

/// A label longer than this is prose that happens to contain a colon, not a
/// fact. The real labels in the wild are short — "ISBN", "Издательство".
const _maxLabelLength = 40;

/// Splits an entry's description into a blurb and a set of fact sections.
///
/// The split is structural, so a feed neither we nor the design has seen still
/// lands somewhere sensible: cut at the first `h1`–`h6`; above it is the blurb,
/// from it down each heading opens a section, `key: value` paragraphs become
/// rows and anything else stays a paragraph. Markup with no headings is left
/// whole in the blurb.
///
/// [markup] is parsed leniently — feeds ship bare `<br>`, stray FB2 tags like
/// `<image l:href>`, and `<p>` nested inside `<p>`.
BookContent parseBookContent(String markup) {
  final blocks = _flatten(html_parser.parseFragment(markup));

  final firstHeading = blocks.indexWhere((b) => b is _Heading);
  if (firstHeading == -1) {
    return BookContent(
      blurb: blocks.whereType<_BlockItem>().map((b) => b.block).toList(),
      details: const [],
    );
  }

  final blurb = blocks
      .take(firstHeading)
      .whereType<_BlockItem>()
      .map((b) => b.block)
      .toList(growable: false);

  final details = <DetailSection>[];
  var rows = <DetailRow>[];
  var notes = <ContentBlock>[];
  String? label;
  var level = 2;

  void closeSection() {
    if (label == null) return;
    details.add(
      DetailSection(label: label, level: level, rows: rows, notes: notes),
    );
    rows = <DetailRow>[];
    notes = <ContentBlock>[];
  }

  for (final item in blocks.skip(firstHeading)) {
    switch (item) {
      case _Heading():
        closeSection();
        label = item.text;
        level = item.level;
      case _BlockItem():
        final block = item.block;
        final row = block is ContentParagraph ? _asRow(block.text) : null;
        if (row != null) {
          rows.add(row);
        } else {
          notes.add(block);
        }
    }
  }
  closeSection();

  return BookContent(blurb: blurb, details: details);
}

/// Splits at the first colon only — values carry colons of their own
/// ("Название: Профессия: ведьма").
DetailRow? _asRow(String text) {
  final colon = text.indexOf(':');
  if (colon <= 0) return null;
  final label = text.substring(0, colon).trim();
  final value = text.substring(colon + 1).trim();
  if (label.isEmpty || value.isEmpty) return null;
  if (label.length > _maxLabelLength) return null;
  return DetailRow(label, value);
}

/// A heading, or a block of content. Headings are kept out of [ContentBlock] so
/// that the block types the UI renders carry no structural role.
sealed class _Item {
  const _Item();
}

class _BlockItem extends _Item {
  final ContentBlock block;
  const _BlockItem(this.block);
}

class _Heading extends _Item {
  final String text;
  final int level;
  const _Heading(this.text, this.level);
}

/// Walks the parsed fragment into a flat list of headings and blocks,
/// unwrapping every element that is not one we render.
List<_Item> _flatten(dom.Node root) {
  final items = <_Item>[];
  var buffer = <ContentSpan>[];

  void flush() {
    final spans = _trimSpans(buffer);
    buffer = <ContentSpan>[];
    if (spans.isEmpty) return;
    items.add(_BlockItem(ContentParagraph(spans)));
  }

  void walk(
    dom.Node node, {
    bool bold = false,
    bool italic = false,
    String? href,
  }) {
    if (node is dom.Text) {
      final text = node.text;
      if (text.isNotEmpty) {
        buffer.add(ContentSpan(text, bold: bold, italic: italic, href: href));
      }
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName ?? '';
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        flush();
        final text = node.text.trim();
        if (text.isNotEmpty) {
          items.add(_Heading(text, int.parse(tag.substring(1))));
        }
      case 'p':
        flush();
        for (final child in node.nodes) {
          walk(child, bold: bold, italic: italic, href: href);
        }
        flush();
      case 'br':
        buffer.add(const ContentSpan('\n'));
      case 'ul' || 'ol':
        flush();
        final items_ = <List<ContentSpan>>[];
        for (final li in node.children.where((e) => e.localName == 'li')) {
          final spans = _trimSpans(_inlineOf(li));
          if (spans.isNotEmpty) items_.add(spans);
        }
        if (items_.isNotEmpty) {
          items.add(
            _BlockItem(ContentBullet(ordered: tag == "ol", items: items_)),
          );
        }
      default:
        // Everything else — <div>, <section>, FB2's <image l:href> — is
        // unwrapped: the tag goes, its children stay.
        final nextBold = bold || _bold.contains(tag);
        final nextItalic = italic || _italic.contains(tag);
        final nextHref = tag == 'a' ? (node.attributes['href'] ?? href) : href;
        for (final child in node.nodes) {
          walk(child, bold: nextBold, italic: nextItalic, href: nextHref);
        }
    }
  }

  for (final child in root.nodes) {
    walk(child);
  }
  flush();
  return items;
}

/// Collects the inline spans of one element, ignoring block structure.
List<ContentSpan> _inlineOf(dom.Element element) {
  final spans = <ContentSpan>[];
  void walk(
    dom.Node node, {
    bool bold = false,
    bool italic = false,
    String? href,
  }) {
    if (node is dom.Text) {
      if (node.text.isNotEmpty) {
        spans.add(
          ContentSpan(node.text, bold: bold, italic: italic, href: href),
        );
      }
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (tag == 'br') {
      spans.add(const ContentSpan('\n'));
      return;
    }
    for (final child in node.nodes) {
      walk(
        child,
        bold: bold || _bold.contains(tag),
        italic: italic || _italic.contains(tag),
        href: tag == 'a' ? (node.attributes['href'] ?? href) : href,
      );
    }
  }

  for (final child in element.nodes) {
    walk(child);
  }
  return spans;
}

/// Collapses runs of whitespace and drops spans that are left with nothing —
/// the shape `<p><b><image l:href="…"/></b></p>` reduces to exactly that.
List<ContentSpan> _trimSpans(List<ContentSpan> spans) {
  final collapsed = <ContentSpan>[];
  for (final span in spans) {
    final text = span.text.replaceAll(RegExp(r'[ \t\r\f ]+'), ' ');
    if (text.isEmpty) continue;
    collapsed.add(
      ContentSpan(text, bold: span.bold, italic: span.italic, href: span.href),
    );
  }
  while (collapsed.isNotEmpty && collapsed.first.text.trim().isEmpty) {
    collapsed.removeAt(0);
  }
  while (collapsed.isNotEmpty && collapsed.last.text.trim().isEmpty) {
    collapsed.removeLast();
  }
  if (collapsed.isEmpty) return const [];

  collapsed[0] = ContentSpan(
    collapsed.first.text.trimLeft(),
    bold: collapsed.first.bold,
    italic: collapsed.first.italic,
    href: collapsed.first.href,
  );
  final last = collapsed.length - 1;
  collapsed[last] = ContentSpan(
    collapsed[last].text.trimRight(),
    bold: collapsed[last].bold,
    italic: collapsed[last].italic,
    href: collapsed[last].href,
  );
  return collapsed.where((s) => s.text.isNotEmpty).toList(growable: false);
}

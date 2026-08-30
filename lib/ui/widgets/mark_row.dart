import 'package:flutter/material.dart';

/// The 38px rounded square that opens a row.
class Mark extends StatelessWidget {
  final Color background;
  final Color border;
  final Widget child;

  const Mark({
    required this.background,
    required this.border,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: child,
    );
  }
}

/// A row that opens with a [Mark]: the square, then a title over an optional
/// quieter line, then whatever the row offers on the right.
///
/// The home screen's catalogues and favourites are drawn this way, and so is
/// a catalogue's root — the root is meant to read as a short list of ways in
/// rather than a feed of entries, so it borrows the home screen's shape
/// deliberately. Keeping the shape here is what holds that resemblance in
/// place; it was two hand-matched copies before.
///
/// The parts that genuinely differ between those screens stay open: each
/// passes its own [padding] and [gap], and its own [subtitle] widget, because
/// no two of them set that line in the same size.
class MarkRow extends StatelessWidget {
  final Widget mark;
  final String title;

  /// The title's colour, defaulting to the scheme's `onSurface`.
  final Color? titleColor;

  final Widget? subtitle;
  final Widget? trailing;

  /// Painted behind the whole row, to set one apart from its neighbours.
  final Color? background;

  final EdgeInsetsGeometry padding;

  /// The space between the mark and the text beside it.
  final double gap;

  final VoidCallback onTap;

  const MarkRow({
    required this.mark,
    required this.title,
    required this.onTap,
    required this.padding,
    required this.gap,
    this.titleColor,
    this.subtitle,
    this.trailing,
    this.background,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: background,
        padding: padding,
        child: Row(
          children: [
            mark,
            SizedBox(width: gap),
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
                      color: titleColor ?? scheme.onSurface,
                    ),
                  ),
                  ?subtitle,
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

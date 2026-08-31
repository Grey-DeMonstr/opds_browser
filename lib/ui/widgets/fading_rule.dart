import 'package:flutter/material.dart';
import 'package:opds_browser/ui/theme.dart';

/// Where a rule fades out.
enum RuleFade {
  /// Fades at both ends, so the rule floats free of the edges it spans.
  bothEnds,

  /// Solid where it starts and faded out at the far end, for a rule anchored
  /// to something — a section label, or the row above it.
  trailing,
}

/// A rule that fades out — the Nocturne signature, drawn where one zone of a
/// screen meets the next.
///
/// It carries the heavier of the design's two weights: [AppPalette.rule], a
/// zone boundary, against [AppPalette.hairline] separating one row from the
/// next. Pass [color] only for a rule that is making a different point, such
/// as the accent under a catalogue root's search row.
class FadingRule extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  /// Overrides [AppPalette.rule], which every ordinary rule should keep.
  final Color? color;

  final RuleFade fade;

  const FadingRule({
    this.margin = EdgeInsets.zero,
    this.color,
    this.fade = RuleFade.bothEnds,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? appPaletteOf(context).rule;
    final faded = color.withValues(alpha: 0);

    return Container(
      height: 1,
      margin: margin,
      decoration: BoxDecoration(
        gradient: switch (fade) {
          RuleFade.bothEnds => LinearGradient(
            stops: const [0, 0.15, 0.85, 1],
            colors: [faded, color, color, faded],
          ),
          RuleFade.trailing => LinearGradient(colors: [color, faded]),
        },
      ),
    );
  }
}

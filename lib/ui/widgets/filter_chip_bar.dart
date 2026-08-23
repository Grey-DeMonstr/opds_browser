import 'package:flutter/material.dart';
import 'package:opds_browser/ui/theme.dart';

/// A small outlined chip, filled with the accent wash when it is the one in
/// effect. The redesign uses these wherever a list can be narrowed.
class NocturneChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const NocturneChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? palette.accentFill : null,
          border: Border.all(
            color: selected ? scheme.outline : scheme.outlineVariant,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rule that fades out at both ends — the Nocturne signature, used where a
/// header meets the list below it.
class FadingRule extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const FadingRule({this.margin = EdgeInsets.zero, super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.14);
    return Container(
      height: 1,
      margin: margin,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          stops: const [0, 0.15, 0.85, 1],
          colors: [
            color.withValues(alpha: 0),
            color,
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

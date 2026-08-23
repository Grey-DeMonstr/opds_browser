import 'package:flutter/material.dart';
import 'package:opds_browser/ui/theme.dart';

/// The redesign's tick box: a 19px rounded square that fills with the solid
/// accent when chosen, and carries a dash when only part of what it covers is.
///
/// [value] is true for chosen, false for not, and null for partly — the same
/// three states Material's tristate [Checkbox] has, drawn to the design.
class NocturneCheckbox extends StatelessWidget {
  final bool? value;
  final VoidCallback onTap;

  /// Announced to screen readers in place of the drawn mark.
  final String? semanticLabel;

  const NocturneCheckbox({
    required this.value,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = appPaletteOf(context);
    final isEmpty = value == false;

    return Semantics(
      label: semanticLabel,
      checked: value ?? false,
      mixed: value == null,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Padding(
          // Keeps the tap target comfortable while the mark stays 19px.
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isEmpty ? null : palette.accentStrong,
              border: Border.all(
                color: isEmpty ? scheme.outline : palette.accentStrong,
                width: 1.5,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(5)),
            ),
            child: isEmpty
                ? null
                : Icon(
                    value == null ? Icons.remove : Icons.check,
                    size: 13,
                    color: scheme.onPrimary,
                  ),
          ),
        ),
      ),
    );
  }
}

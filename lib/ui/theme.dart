import 'package:flutter/material.dart';

/// Colour tokens from the Nocturne design system (`_ds/nocturne/styles.css`),
/// as drawn in the dark screens of the redesign.
///
/// Only the steps the app actually paints are listed. [NocturneLight] holds
/// the light half.
abstract final class Nocturne {
  static const bg = Color(0xFF161826);
  static const surface = Color(0xFF232532);
  static const text = Color(0xFFE9E9ED);
  static const accent = Color(0xFF9184D9);

  static const accent200 = Color(0xFFE7E5FE);
  static const accent300 = Color(0xFFD2CEFD);
  static const accent400 = Color(0xFFB5ABFC);
  static const accent700 = Color(0xFF5D5294);
  static const accent800 = Color(0xFF423A6A);
  static const accent900 = Color(0xFF2B2741);

  static const neutral900 = Color(0xFF292B31);

  /// Row meta and secondary labels.
  static const muted = Color(0xFF8C8C96);

  /// The quietest step — overflow icons, unit words.
  static const dim = Color(0xFF6F6F7A);

  /// App-bar action icons, which trail.
  static const iconRest = Color(0xFFB6B6BF);

  /// App-bar leading icons, a step brighter than [iconRest].
  static const iconStrong = Color(0xFFC9C9D1);

  /// The ground a catalogue mark sits on — between [bg] and [surface].
  static const markSurface = Color(0xFF1E2030);

  /// The ground a selection card sits on.
  static const cardSurface = Color(0xFF1B1D2B);

  /// Numerals in the browse list's count column.
  static const countText = Color(0xFFC9C9D1);

  static const hairline = Color(0x0DE9E9ED);
  static const cardBorder = Color(0x17E9E9ED);
}

/// The same system with the ramp inverted: a paper ground, and the accent
/// stepped down to hold its contrast on white.
abstract final class NocturneLight {
  static const bg = Color(0xFFF6F6F8);
  static const text = Color(0xFF1A1C28);

  /// The stepped-down accent — borders, marks, the favourites label.
  static const accent = Color(0xFF5B4EB0);

  /// The accent as text, one step darker again.
  static const accentText = Color(0xFF4C4098);

  static const accentTint = Color(0xFFE7E4F8);
  static const accentEdge = Color(0xFFC7C0EE);

  /// Row meta and secondary labels.
  static const muted = Color(0xFF75778A);

  /// The quietest step — overflow icons, unit words.
  static const dim = Color(0xFF9A9CAB);

  /// App-bar action icons, which trail.
  static const iconRest = Color(0xFF585A68);

  /// App-bar leading icons. On paper both icon roles read the same.
  static const iconStrong = Color(0xFF585A68);

  static const edge = Color(0xFFE0E0E6);

  /// A catalogue mark sits on paper white, above the ground.
  static const markSurface = Color(0xFFFFFFFF);

  /// So does a selection card.
  static const cardSurface = Color(0xFFFFFFFF);

  /// Numerals in the browse list's count column.
  static const countText = Color(0xFF3A3C4A);

  static const hairline = Color(0xFFEBEBF0);
  static const cardBorder = Color(0xFFE2E2E8);
}

/// Roles the redesign needs that [ColorScheme] has no slot for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Edge of the letter mark on a favourite row.
  final Color favoriteMarkBorder;

  /// Fill behind the icon mark on a catalogue row.
  final Color catalogMarkSurface;

  /// The quietest step in the system: row overflow icons, the unit word beside
  /// a count, the line saying editions were folded together.
  final Color dim;

  /// Rules between rows, and between the books inside a selection card.
  final Color hairline;

  /// The ground a selection card sits on.
  final Color cardSurface;

  /// The edge of a selection card.
  final Color cardBorder;

  /// The solid accent — a checked box, the edge of an outlined action. On the
  /// dark theme this is darker than [ColorScheme.primary], which is tuned as a
  /// text colour and would glare as a fill.
  final Color accentStrong;

  /// [accentStrong] as a wash, behind a selected chip.
  final Color accentFill;

  /// A prefix bucket's title in the browse list.
  final Color bucketLabel;

  /// Numerals in the browse list's count column.
  final Color countText;

  const AppPalette({
    required this.favoriteMarkBorder,
    required this.catalogMarkSurface,
    required this.dim,
    required this.hairline,
    required this.cardSurface,
    required this.cardBorder,
    required this.accentStrong,
    required this.accentFill,
    required this.bucketLabel,
    required this.countText,
  });

  factory AppPalette.dark() => AppPalette(
    favoriteMarkBorder: Nocturne.accent800,
    catalogMarkSurface: Nocturne.markSurface,
    dim: Nocturne.dim,
    hairline: Nocturne.hairline,
    cardSurface: Nocturne.cardSurface,
    cardBorder: Nocturne.cardBorder,
    accentStrong: Nocturne.accent,
    accentFill: Nocturne.accent.withValues(alpha: 0.14),
    bucketLabel: Nocturne.accent400,
    countText: Nocturne.countText,
  );

  factory AppPalette.light() => AppPalette(
    favoriteMarkBorder: NocturneLight.accentEdge,
    catalogMarkSurface: NocturneLight.markSurface,
    dim: NocturneLight.dim,
    hairline: NocturneLight.hairline,
    cardSurface: NocturneLight.cardSurface,
    cardBorder: NocturneLight.cardBorder,
    accentStrong: NocturneLight.accent,
    accentFill: NocturneLight.accent.withValues(alpha: 0.09),
    bucketLabel: NocturneLight.accentText,
    countText: NocturneLight.countText,
  );

  @override
  AppPalette copyWith({
    Color? favoriteMarkBorder,
    Color? catalogMarkSurface,
    Color? dim,
    Color? hairline,
    Color? cardSurface,
    Color? cardBorder,
    Color? accentStrong,
    Color? accentFill,
    Color? bucketLabel,
    Color? countText,
  }) => AppPalette(
    favoriteMarkBorder: favoriteMarkBorder ?? this.favoriteMarkBorder,
    catalogMarkSurface: catalogMarkSurface ?? this.catalogMarkSurface,
    dim: dim ?? this.dim,
    hairline: hairline ?? this.hairline,
    cardSurface: cardSurface ?? this.cardSurface,
    cardBorder: cardBorder ?? this.cardBorder,
    accentStrong: accentStrong ?? this.accentStrong,
    accentFill: accentFill ?? this.accentFill,
    bucketLabel: bucketLabel ?? this.bucketLabel,
    countText: countText ?? this.countText,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      favoriteMarkBorder: Color.lerp(
        favoriteMarkBorder,
        other.favoriteMarkBorder,
        t,
      )!,
      catalogMarkSurface: Color.lerp(
        catalogMarkSurface,
        other.catalogMarkSurface,
        t,
      )!,
      dim: Color.lerp(dim, other.dim, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      bucketLabel: Color.lerp(bucketLabel, other.bucketLabel, t)!,
      countText: Color.lerp(countText, other.countText, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.favoriteMarkBorder == favoriteMarkBorder &&
      other.catalogMarkSurface == catalogMarkSurface &&
      other.dim == dim &&
      other.hairline == hairline &&
      other.cardSurface == cardSurface &&
      other.cardBorder == cardBorder &&
      other.accentStrong == accentStrong &&
      other.accentFill == accentFill &&
      other.bucketLabel == bucketLabel &&
      other.countText == countText;

  @override
  int get hashCode => Object.hash(
    favoriteMarkBorder,
    catalogMarkSurface,
    dim,
    hairline,
    cardSurface,
    cardBorder,
    accentStrong,
    accentFill,
    bucketLabel,
    countText,
  );
}

/// Reads the [AppPalette] off the ambient theme.
AppPalette appPaletteOf(BuildContext context) =>
    Theme.of(context).extension<AppPalette>()!;

/// The horizontal inset a screen's content keeps from the edge.
///
/// Shared by the headers, the chips and every row, so that a title on one
/// screen lines up with a title on the next. The home screen keeps its own,
/// wider, inset — see `start_screen.dart`.
const gutter = 16.0;

ThemeData buildDarkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Nocturne.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Nocturne.accent400,
        onPrimary: Nocturne.bg,
        primaryContainer: Nocturne.accent900,
        onPrimaryContainer: Nocturne.accent300,
        secondary: Nocturne.accent300,
        onSecondary: Nocturne.bg,
        surface: Nocturne.bg,
        onSurface: Nocturne.text,
        surfaceContainerLowest: Nocturne.bg,
        surfaceContainerLow: Nocturne.markSurface,
        surfaceContainer: Nocturne.markSurface,
        surfaceContainerHigh: Nocturne.surface,
        surfaceContainerHighest: Nocturne.surface,
        onSurfaceVariant: Nocturne.muted,
        outline: Nocturne.accent700,
        outlineVariant: Nocturne.neutral900,
      );

  return _base(scheme).copyWith(
    extensions: [AppPalette.dark()],
    appBarTheme: _appBarTheme(scheme).copyWith(
      iconTheme: const IconThemeData(color: Nocturne.iconStrong, size: 21),
      actionsIconTheme: const IconThemeData(color: Nocturne.iconRest, size: 21),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Nocturne.accent300,
        backgroundColor: Nocturne.accent.withValues(alpha: 0.08),
        side: const BorderSide(color: Nocturne.accent),
      ).merge(_outlinedButtonShape),
    ),
  );
}

ThemeData buildLightTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: NocturneLight.accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: NocturneLight.accent,
        onPrimary: Colors.white,
        primaryContainer: NocturneLight.accentTint,
        onPrimaryContainer: NocturneLight.accentText,
        secondary: NocturneLight.accentText,
        onSecondary: Colors.white,
        surface: NocturneLight.bg,
        onSurface: NocturneLight.text,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: NocturneLight.bg,
        surfaceContainerHigh: NocturneLight.bg,
        surfaceContainerHighest: NocturneLight.bg,
        onSurfaceVariant: NocturneLight.muted,
        outline: NocturneLight.accentEdge,
        outlineVariant: NocturneLight.edge,
      );

  return _base(scheme).copyWith(
    extensions: [AppPalette.light()],
    appBarTheme: _appBarTheme(scheme).copyWith(
      iconTheme: const IconThemeData(color: NocturneLight.iconStrong, size: 21),
      actionsIconTheme: const IconThemeData(
        color: NocturneLight.iconRest,
        size: 21,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NocturneLight.accentText,
        backgroundColor: NocturneLight.accent.withValues(alpha: 0.06),
        side: const BorderSide(color: NocturneLight.accent),
      ).merge(_outlinedButtonShape),
    ),
  );
}

/// Everything both themes share: the typeface and the flat, tint-free chrome
/// the redesign is drawn against.
ThemeData _base(ColorScheme scheme) =>
    ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Inter');

AppBarTheme _appBarTheme(ColorScheme scheme) => AppBarTheme(
  backgroundColor: scheme.surface,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  titleTextStyle: TextStyle(
    fontFamily: 'Inter',
    fontSize: 23,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.23,
    color: scheme.onSurface,
  ),
  iconTheme: IconThemeData(color: scheme.onSurface, size: 21),
  actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 21),
);

/// The 1a action button: an 8px-radius outline, not a Material pill.
final ButtonStyle _outlinedButtonShape = OutlinedButton.styleFrom(
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
  textStyle: const TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
  ),
);

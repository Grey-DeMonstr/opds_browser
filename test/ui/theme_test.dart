import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/ui/theme.dart';

void main() {
  test('dark theme paints the Nocturne ground', () {
    expect(buildDarkTheme().colorScheme.surface, const Color(0xFF161826));
  });

  test('dark theme takes its accent from the Nocturne accent ramp', () {
    expect(buildDarkTheme().colorScheme.primary, const Color(0xFFB5ABFC));
  });

  test('light theme paints the paper ground', () {
    final theme = buildLightTheme();
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.surface, const Color(0xFFF6F6F8));
    expect(theme.colorScheme.onSurface, const Color(0xFF1A1C28));
  });

  test('light theme steps the accent down so it holds on paper', () {
    expect(buildLightTheme().colorScheme.primary, const Color(0xFF5B4EB0));
  });

  test('light palette takes the row tokens from the light design', () {
    final palette = buildLightTheme().extension<AppPalette>()!;
    expect(palette.favoriteMarkBorder, const Color(0xFFC7C0EE));
    expect(palette.catalogMarkSurface, const Color(0xFFFFFFFF));
    expect(palette.dim, const Color(0xFF9A9CAB));
  });

  test('dark palette carries the browse and selection roles', () {
    final palette = buildDarkTheme().extension<AppPalette>()!;
    expect(palette.dim, const Color(0xFF6F6F7A));
    expect(palette.bucketLabel, const Color(0xFFB5ABFC));
    expect(palette.countText, const Color(0xFFC9C9D1));
    expect(palette.cardSurface, const Color(0xFF1B1D2B));
    expect(palette.accentStrong, const Color(0xFF9184D9));
  });

  test('light palette carries the browse and selection roles', () {
    final palette = buildLightTheme().extension<AppPalette>()!;
    expect(palette.bucketLabel, const Color(0xFF4C4098));
    expect(palette.countText, const Color(0xFF3A3C4A));
    expect(palette.cardSurface, const Color(0xFFFFFFFF));
    expect(palette.cardBorder, const Color(0xFFE2E2E8));
    expect(palette.accentStrong, const Color(0xFF5B4EB0));
  });

  test('a checked box fills with the solid accent in both themes', () {
    expect(
      buildDarkTheme().extension<AppPalette>()!.accentStrong,
      isNot(buildDarkTheme().colorScheme.primary),
    );
    expect(
      buildLightTheme().extension<AppPalette>()!.accentStrong,
      buildLightTheme().colorScheme.primary,
    );
  });

  test('both themes set Inter as the text font', () {
    expect(buildDarkTheme().textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(buildLightTheme().textTheme.bodyMedium?.fontFamily, 'Inter');
  });

  test('both themes carry an AppPalette', () {
    expect(buildDarkTheme().extension<AppPalette>(), isNotNull);
    expect(buildLightTheme().extension<AppPalette>(), isNotNull);
  });

  test('AppPalette.lerp at t=0 keeps the starting colours', () {
    final dark = buildDarkTheme().extension<AppPalette>()!;
    final light = buildLightTheme().extension<AppPalette>()!;
    expect(dark.lerp(light, 0), dark);
  });

  test('AppPalette.lerp at t=1 reaches the target colours', () {
    final dark = buildDarkTheme().extension<AppPalette>()!;
    final light = buildLightTheme().extension<AppPalette>()!;
    expect(dark.lerp(light, 1), light);
  });
}

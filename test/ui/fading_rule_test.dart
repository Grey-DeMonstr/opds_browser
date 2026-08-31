import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/ui/theme.dart';
import 'package:opds_browser/ui/widgets/fading_rule.dart';

void main() {
  /// The gradient the one rule in [child] is painted with.
  Future<LinearGradient> gradientOf(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(FadingRule),
        matching: find.byType(Container),
      ),
    );
    return (container.decoration! as BoxDecoration).gradient! as LinearGradient;
  }

  testWidgets('a rule takes the palette\'s rule weight, not a local alpha', (
    tester,
  ) async {
    final gradient = await gradientOf(tester, const FadingRule());
    final rule = buildDarkTheme().extension<AppPalette>()!.rule;

    // The opaque middle of the gradient is the rule's own colour; the ends are
    // that same colour faded out.
    expect(gradient.colors[1], rule);
  });

  testWidgets('a rule can be given a colour of its own', (tester) async {
    const accent = Color(0xFF9184D9);
    final gradient = await gradientOf(tester, const FadingRule(color: accent));

    expect(gradient.colors[1], accent);
  });

  testWidgets('by default a rule fades out at both ends', (tester) async {
    final gradient = await gradientOf(tester, const FadingRule());

    expect(gradient.stops, const [0, 0.15, 0.85, 1]);
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last.a, 0);
    expect(gradient.colors[1].a, greaterThan(0));
  });

  testWidgets('a trailing rule is solid where it starts and fades out once', (
    tester,
  ) async {
    final gradient = await gradientOf(
      tester,
      const FadingRule(fade: RuleFade.trailing),
    );

    expect(gradient.colors.first.a, greaterThan(0));
    expect(gradient.colors.last.a, 0);
    expect(
      gradient.colors.length,
      2,
      reason: 'anchored at one end, it needs no middle',
    );
  });
}

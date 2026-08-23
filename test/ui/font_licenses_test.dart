import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/ui/font_licenses.dart';

void main() {
  setUp(LicenseRegistry.reset);

  testWidgets('the bundled Inter font ships its licence', (tester) async {
    registerFontLicenses();

    final entries = await LicenseRegistry.licenses
        .where((e) => e.packages.contains('Inter'))
        .toList();

    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('Copyright (c) 2016 The Inter Project Authors'));
    expect(text, contains('SIL OPEN FONT LICENSE'));
  });
}

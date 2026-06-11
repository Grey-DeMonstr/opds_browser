import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/app.dart';

void main() {
  testWidgets('App renders the placeholder home', (tester) async {
    await tester.pumpWidget(const OpdsBrowserApp());
    expect(find.text('OPDS Browser'), findsOneWidget);
  });
}

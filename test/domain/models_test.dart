import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/models.dart';

void main() {
  group('AcquisitionLink', () {
    test('toJson / fromJson roundtrip', () {
      final link = AcquisitionLink(
        url: Uri.parse('https://example.com/book.fb2'),
        mimeType: 'application/fb2',
        formatLabel: 'FB2',
      );
      final json = link.toJson();
      expect(json['url'], 'https://example.com/book.fb2');
      expect(json['mimeType'], 'application/fb2');
      expect(json['formatLabel'], 'FB2');
      final restored = AcquisitionLink.fromJson(json);
      expect(restored.url, link.url);
      expect(restored.mimeType, link.mimeType);
      expect(restored.formatLabel, link.formatLabel);
    });
  });
}

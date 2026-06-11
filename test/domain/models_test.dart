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

  group('NavigationEntry', () {
    test('toJson / fromJson roundtrip — with subtitle', () {
      final entry = NavigationEntry(
        title: 'Science Fiction',
        subtitle: 'Explore the cosmos',
        url: Uri.parse('https://example.com/sci-fi'),
      );
      final json = entry.toJson();
      expect(json['type'], 'nav');
      expect(json['title'], 'Science Fiction');
      expect(json['subtitle'], 'Explore the cosmos');
      expect(json['url'], 'https://example.com/sci-fi');
      final restored = NavigationEntry.fromJson(json);
      expect(restored.title, entry.title);
      expect(restored.subtitle, entry.subtitle);
      expect(restored.url, entry.url);
    });

    test('toJson omits subtitle when null; fromJson restores null', () {
      final entry = NavigationEntry(
        title: 'Fantasy',
        subtitle: null,
        url: Uri.parse('https://example.com/fantasy'),
      );
      final json = entry.toJson();
      expect(json.containsKey('subtitle'), isFalse);
      final restored = NavigationEntry.fromJson(json);
      expect(restored.subtitle, isNull);
    });
  });
}

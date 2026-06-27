import 'package:flutter_test/flutter_test.dart';
import 'package:opds_browser/domain/entities.dart';

void main() {
  group('Catalog', () {
    test('stores all fields', () {
      final c = Catalog(
        id: 1,
        title: 'Test Catalog',
        rootUrl: Uri.parse('https://example.com/opds'),
        protocol: 'opds1',
      );
      expect(c.id, 1);
      expect(c.title, 'Test Catalog');
      expect(c.rootUrl, Uri.parse('https://example.com/opds'));
      expect(c.protocol, 'opds1');
    });
  });

  group('Favorite', () {
    test('stores all fields', () {
      final f = Favorite(
        id: 2,
        catalogId: 1,
        url: Uri.parse('https://example.com/opds/sci-fi'),
        title: 'Science Fiction',
        sortOrder: 0,
      );
      expect(f.id, 2);
      expect(f.catalogId, 1);
      expect(f.url, Uri.parse('https://example.com/opds/sci-fi'));
      expect(f.title, 'Science Fiction');
      expect(f.sortOrder, 0);
    });
  });

  group('CustomSafFolder', () {
    test('stores uriString and displayName', () {
      const d = CustomSafFolder('content://com.example/tree/doc', 'My Folder');
      expect(d.uriString, 'content://com.example/tree/doc');
      expect(d.displayName, 'My Folder');
    });
  });

  group('AppSettings', () {
    test('defaults target to null and folder flags to false', () {
      const s = AppSettings();
      expect(s.target, isNull);
      expect(s.createAuthorFolder, isFalse);
      expect(s.createSeriesFolder, isFalse);
    });

    test('stores custom target and folder flags', () {
      const s = AppSettings(
        target: CustomSafFolder('content://uri', 'Folder'),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(s.target?.uriString, 'content://uri');
      expect(s.createAuthorFolder, isTrue);
      expect(s.createSeriesFolder, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const s = AppSettings(target: CustomSafFolder('u', 'F'));
      final s2 = s.copyWith(createAuthorFolder: true);
      expect(s2.createAuthorFolder, isTrue);
      expect(s2.createSeriesFolder, isFalse);
      expect(s2.target?.uriString, 'u');
    });

    test('copyWith can replace target', () {
      const s = AppSettings(createAuthorFolder: true);
      final s2 = s.copyWith(target: const CustomSafFolder('u', 'F'));
      expect(s2.target?.uriString, 'u');
      expect(s2.createAuthorFolder, isTrue);
    });

    test('copyWith with clearTarget=true sets target to null', () {
      const s = AppSettings(target: CustomSafFolder('u', 'F'));
      final s2 = s.copyWith(clearTarget: true);
      expect(s2.target, isNull);
    });
  });
}

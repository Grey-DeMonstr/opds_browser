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

  group('DownloadTarget', () {
    test('SystemDownloads is a DownloadTarget', () {
      const d = SystemDownloads();
      expect(d, isA<DownloadTarget>());
    });

    test('CustomSafFolder stores uriString', () {
      const d = CustomSafFolder('content://com.example/tree/doc', 'doc');
      expect(d, isA<DownloadTarget>());
      expect(d.uriString, 'content://com.example/tree/doc');
    });

    test('CustomSafFolder stores displayName', () {
      const d = CustomSafFolder('content://com.example/tree/doc', 'My Downloads');
      expect(d.displayName, 'My Downloads');
    });
  });

  group('AppSettings', () {
    test('defaults createAuthorFolder and createSeriesFolder to false', () {
      const s = AppSettings(target: SystemDownloads());
      expect(s.createAuthorFolder, isFalse);
      expect(s.createSeriesFolder, isFalse);
      expect(s.target, isA<SystemDownloads>());
    });

    test('stores custom target and folder flags', () {
      const s = AppSettings(
        target: CustomSafFolder('content://uri', 'Folder'),
        createAuthorFolder: true,
        createSeriesFolder: true,
      );
      expect(s.target, isA<CustomSafFolder>());
      expect((s.target as CustomSafFolder).uriString, 'content://uri');
      expect(s.createAuthorFolder, isTrue);
      expect(s.createSeriesFolder, isTrue);
    });

    test('copyWith creates updated copy preserving unchanged fields', () {
      const s = AppSettings(target: SystemDownloads());
      final s2 = s.copyWith(createAuthorFolder: true);
      expect(s2.createAuthorFolder, isTrue);
      expect(s2.createSeriesFolder, isFalse);
      expect(s2.target, isA<SystemDownloads>());
    });

    test('copyWith can change target', () {
      const s = AppSettings(target: SystemDownloads(), createAuthorFolder: true);
      final s2 = s.copyWith(target: const CustomSafFolder('u', 'F'));
      expect(s2.target, isA<CustomSafFolder>());
      expect(s2.createAuthorFolder, isTrue);
    });
  });
}

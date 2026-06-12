import 'package:opds_browser/data/opds_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart'; // ignore: unused_import

String mimeToLabel(String mimeType) => switch (mimeType) {
      'application/fb2' || 'application/x-fictionbook+xml' => 'FB2',
      'application/fb2+zip' || 'application/x-zip-compressed-fb2' => 'FB2.ZIP',
      'application/epub+zip' => 'EPUB',
      'application/pdf' => 'PDF',
      'application/x-mobipocket-ebook' => 'MOBI',
      _ => mimeType.split('/').last.toUpperCase(),
    };

class Opds1FeedParser implements OpdsFeedParser {
  @override
  ParsedFeed parse(List<int> bytes, Uri feedUrl) =>
      throw UnimplementedError('parse not yet implemented');
}

import 'package:opds_browser/domain/models.dart';

abstract interface class OpdsFeedParser {
  /// Parses raw HTTP response [bytes] into a [ParsedFeed].
  /// [feedUrl] is the URL the bytes came from; used to resolve relative hrefs
  /// when [xml:base] is absent from the feed element.
  /// Throws [ParseException] on malformed or unrecognised content.
  ParsedFeed parse(List<int> bytes, Uri feedUrl);
}

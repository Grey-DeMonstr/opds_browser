import 'package:http/http.dart' as http;
import 'package:opds_browser/data/opds_feed_parser.dart';
import 'package:opds_browser/data/opds_http_fetcher.dart';
import 'package:opds_browser/data/opds1/opds1_feed_parser.dart';
import 'package:opds_browser/domain/models.dart';
import 'package:opds_browser/domain/opds_client.dart';

class Opds1Client implements OpdsClient {
  final OpdsHttpFetcher _fetcher;
  final OpdsFeedParser _parser;

  /// Production constructor: wraps [httpClient] in an [OpdsHttpFetcher]
  /// and uses the default [Opds1FeedParser].
  Opds1Client(http.Client httpClient)
      : _fetcher = OpdsHttpFetcher(httpClient),
        _parser = Opds1FeedParser();

  /// Test constructor: inject both collaborators directly.
  Opds1Client.withDependencies(this._fetcher, this._parser);

  @override
  Future<ParsedFeed> fetchFeed(Uri url) async {
    final bytes = await _fetcher.fetch(url);
    return _parser.parse(bytes, url);
  }

  @override
  Future<bool> probe(Uri url) async {
    try {
      await fetchFeed(url);
      return true;
    } on ParseException {
      return false;
    } on UnsupportedProtocolException {
      return false;
    }
    // NetworkException and HttpStatusException propagate to caller.
  }
}

import 'package:xml/xml.dart';
import 'package:opds_browser/domain/opds_client.dart';

const _openSearchNs = 'http://a9.com/-/spec/opensearch/1.1/';

/// Media types a `<Url>` may declare that the feed parser can actually read.
const _feedTypeHint = 'atom';

/// The search template an OpenSearch description [document] holds, or null
/// when it offers none the app can use.
///
/// A description document may list several `<Url>` elements, one per output
/// type; a browser-facing `text/html` one is common and comes first as often
/// as not. Following that would fetch a web page the feed parser cannot read,
/// so an Atom template is preferred and the first template is only a fallback.
///
/// Throws [ParseException] for a document that does not parse, or that is not
/// an OpenSearch description at all.
String? parseOpenSearchTemplate(String document) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(document);
  } on XmlException catch (e) {
    throw ParseException('not valid XML: ${e.message}');
  }

  final root = doc.rootElement;
  if (root.localName != 'OpenSearchDescription' &&
      root.name.namespaceUri != _openSearchNs) {
    throw ParseException(
      'not an OpenSearch description: <${root.name.qualified}>',
    );
  }

  final urls = root.childElements
      .where((e) => e.localName == 'Url')
      .where((e) => (e.getAttribute('template') ?? '').isNotEmpty)
      .toList();
  if (urls.isEmpty) return null;

  final atom = urls.where(
    (e) => (e.getAttribute('type') ?? '').toLowerCase().contains(_feedTypeHint),
  );
  final chosen = atom.isNotEmpty ? atom.first : urls.first;
  return chosen.getAttribute('template');
}

import 'package:opds_browser/domain/models.dart';

/// The media type an OpenSearch description document declares.
const openSearchDescriptionType = 'application/opensearchdescription+xml';

/// The macro a catalogue leaves for the query in a search template.
const searchTermsMacro = '{searchTerms}';

final _mediaTypeParameters = RegExp(r';.*$');
final _anyMacro = RegExp(r'\{[^{}]*\}');

/// True when [link] points at an OpenSearch description document — one that
/// must be fetched before the catalogue can be searched.
bool isOpenSearchDescription(SearchLink link) {
  final type = link.type;
  if (type == null) return false;
  return type.replaceAll(_mediaTypeParameters, '').trim().toLowerCase() ==
      openSearchDescriptionType;
}

/// [link]'s href with percent-encoding undone, so the macro reads as the
/// catalogue wrote it.
///
/// Resolving an href against the feed's base yields a [Uri], and [Uri]
/// normalises `{` and `}` to `%7B` and `%7D`. Every check and substitution
/// works on this decoded form; nothing else should read `link.url` directly.
String searchTemplateOf(SearchLink link) => Uri.decodeFull(link.url.toString());

/// True when [link] is itself the template — its href carries the macro, so
/// substituting into it is all the catalogue asks for.
bool isSearchTemplate(SearchLink link) =>
    searchTemplateOf(link).contains(searchTermsMacro);

/// The link to search [links] through, or null when the catalogue cannot be
/// searched at all.
///
/// A direct template wins over a description document: substituting into it
/// costs no round trip, and a catalogue commonly advertises both. A link that
/// is neither is not offered — the app says a catalogue cannot be searched
/// rather than guessing a URL for it.
SearchLink? preferredSearchLink(List<SearchLink> links) {
  for (final link in links) {
    if (isSearchTemplate(link)) return link;
  }
  for (final link in links) {
    if (isOpenSearchDescription(link)) return link;
  }
  return null;
}

/// Substitutes [terms] into an OpenSearch [template].
///
/// The query is percent-encoded as UTF-8, which is what catalogues expect even
/// when they serve their feeds in another encoding. Every other macro is
/// emptied rather than left in place: the app supplies none of them, and a
/// brace-wrapped name reaching the server as a literal is worse than a blank.
Uri expandSearchTemplate(String template, String terms) {
  final withTerms = template.replaceAll(
    searchTermsMacro,
    Uri.encodeComponent(terms),
  );
  return Uri.parse(withTerms.replaceAll(_anyMacro, ''));
}

/// [template] made absolute against [base], with the macro still readable.
///
/// A description document commonly publishes a root-relative template, which
/// only means anything alongside the URL the document itself came from.
String absoluteSearchTemplate(Uri base, String template) =>
    Uri.decodeFull(base.resolve(template).toString());

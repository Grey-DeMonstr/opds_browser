class AcquisitionLink {
  final Uri url;
  final String mimeType;
  final String formatLabel;

  const AcquisitionLink({
    required this.url,
    required this.mimeType,
    required this.formatLabel,
  });

  Map<String, dynamic> toJson() => {
        'url': url.toString(),
        'mimeType': mimeType,
        'formatLabel': formatLabel,
      };

  factory AcquisitionLink.fromJson(Map<String, dynamic> json) => AcquisitionLink(
        url: Uri.parse(json['url'] as String),
        mimeType: json['mimeType'] as String,
        formatLabel: json['formatLabel'] as String,
      );
}

/// Sealed base for feed entries. [fromJson] is added in Task 6
/// once all subclasses exist.
sealed class FeedEntry {
  const FeedEntry();
  Map<String, dynamic> toJson();
}

class NavigationEntry extends FeedEntry {
  final String title;
  final String? subtitle;
  final Uri url;

  const NavigationEntry({
    required this.title,
    this.subtitle,
    required this.url,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'nav',
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'url': url.toString(),
      };

  factory NavigationEntry.fromJson(Map<String, dynamic> json) => NavigationEntry(
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        url: Uri.parse(json['url'] as String),
      );
}

class BookEntry extends FeedEntry {
  final String title;
  final List<String> authors;
  final String? series;
  final double? seriesIndex;
  final String? summary;
  final Uri? coverUrl;
  final List<AcquisitionLink> acquisitionLinks;

  const BookEntry({
    required this.title,
    required this.authors,
    this.series,
    this.seriesIndex,
    this.summary,
    this.coverUrl,
    required this.acquisitionLinks,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'book',
        'title': title,
        'authors': authors,
        if (series != null) 'series': series,
        if (seriesIndex != null) 'seriesIndex': seriesIndex,
        if (summary != null) 'summary': summary,
        if (coverUrl != null) 'coverUrl': coverUrl.toString(),
        'acquisitionLinks': acquisitionLinks.map((l) => l.toJson()).toList(),
      };

  factory BookEntry.fromJson(Map<String, dynamic> json) => BookEntry(
        title: json['title'] as String,
        authors: (json['authors'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        series: json['series'] as String?,
        seriesIndex: (json['seriesIndex'] as num?)?.toDouble(),
        summary: json['summary'] as String?,
        coverUrl: json['coverUrl'] != null
            ? Uri.parse(json['coverUrl'] as String)
            : null,
        acquisitionLinks: (json['acquisitionLinks'] as List<dynamic>)
            .map((l) => AcquisitionLink.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

class ParsedFeed {
  const ParsedFeed();
}

class CachedFeed {
  const CachedFeed();
}

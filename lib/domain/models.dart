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

  factory AcquisitionLink.fromJson(Map<String, dynamic> json) =>
      AcquisitionLink(
        url: Uri.parse(json['url'] as String),
        mimeType: json['mimeType'] as String,
        formatLabel: json['formatLabel'] as String,
      );
}

sealed class FeedEntry {
  const FeedEntry();
  Map<String, dynamic> toJson();

  static FeedEntry fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'nav' => NavigationEntry.fromJson(json),
      'book' => BookEntry.fromJson(json),
      _ => throw FormatException('unknown FeedEntry type: $type'),
    };
  }
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

  factory NavigationEntry.fromJson(Map<String, dynamic> json) =>
      NavigationEntry(
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

  /// The description as plain text — what list rows show.
  final String? summary;

  /// The description as the feed's own markup, when it sent markup at all.
  /// Kept unparsed: the book page splits it, nothing else needs it, and
  /// splitting every entry of a 200-book feed up front would be wasted work.
  final String? contentHtml;

  /// `category/@label`, falling back to `@term`.
  final List<String> categories;
  final Uri? coverUrl;
  final List<AcquisitionLink> acquisitionLinks;

  const BookEntry({
    required this.title,
    required this.authors,
    this.series,
    this.seriesIndex,
    this.summary,
    this.contentHtml,
    this.categories = const [],
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
    if (contentHtml != null) 'contentHtml': contentHtml,
    if (categories.isNotEmpty) 'categories': categories,
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
    contentHtml: json['contentHtml'] as String?,
    categories:
        (json['categories'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        const [],
    coverUrl: json['coverUrl'] != null
        ? Uri.parse(json['coverUrl'] as String)
        : null,
    acquisitionLinks: (json['acquisitionLinks'] as List<dynamic>)
        .map((l) => AcquisitionLink.fromJson(l as Map<String, dynamic>))
        .toList(),
  );
}

class ParsedFeed {
  final String title;
  final List<FeedEntry> entries;
  final Uri? nextPageUrl;

  const ParsedFeed({
    required this.title,
    required this.entries,
    this.nextPageUrl,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'entries': entries.map((e) => e.toJson()).toList(),
    if (nextPageUrl != null) 'nextPageUrl': nextPageUrl.toString(),
  };

  factory ParsedFeed.fromJson(Map<String, dynamic> json) => ParsedFeed(
    title: json['title'] as String,
    entries: (json['entries'] as List<dynamic>)
        .map((e) => FeedEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextPageUrl: json['nextPageUrl'] != null
        ? Uri.parse(json['nextPageUrl'] as String)
        : null,
  );
}

class CachedFeed {
  final ParsedFeed feed;
  final DateTime fetchedAt;
  final bool fromCache;

  const CachedFeed({
    required this.feed,
    required this.fetchedAt,
    required this.fromCache,
  });
}

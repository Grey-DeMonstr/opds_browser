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

// Stubs — replaced in Tasks 5 and 6.
class BookEntry extends FeedEntry {
  const BookEntry();
  @override
  Map<String, dynamic> toJson() => const {};
}

class ParsedFeed {
  const ParsedFeed();
}

class CachedFeed {
  const CachedFeed();
}

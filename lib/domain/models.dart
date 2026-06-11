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

// Stubs to allow opds_client.dart and repositories.dart to compile.
// Replaced with full implementations in Tasks 4–6.
class ParsedFeed {
  const ParsedFeed();
}

class CachedFeed {
  const CachedFeed();
}

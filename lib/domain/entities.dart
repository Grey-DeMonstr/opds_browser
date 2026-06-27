sealed class DownloadTarget {
  const DownloadTarget();
}

class SystemDownloads extends DownloadTarget {
  const SystemDownloads();
}

class CustomSafFolder extends DownloadTarget {
  final String uriString;
  final String displayName;
  const CustomSafFolder(this.uriString, this.displayName);
}

class Catalog {
  final int id;
  final String title;
  final Uri rootUrl;
  final String protocol;

  const Catalog({
    required this.id,
    required this.title,
    required this.rootUrl,
    required this.protocol,
  });
}

class Favorite {
  final int id;
  final int catalogId;
  final Uri url;
  final String title;
  final int sortOrder;

  const Favorite({
    required this.id,
    required this.catalogId,
    required this.url,
    required this.title,
    required this.sortOrder,
  });
}

class AppSettings {
  final DownloadTarget target;
  final bool createAuthorFolder;
  final bool createSeriesFolder;

  const AppSettings({
    required this.target,
    this.createAuthorFolder = false,
    this.createSeriesFolder = false,
  });

  AppSettings copyWith({
    DownloadTarget? target,
    bool? createAuthorFolder,
    bool? createSeriesFolder,
  }) => AppSettings(
    target: target ?? this.target,
    createAuthorFolder: createAuthorFolder ?? this.createAuthorFolder,
    createSeriesFolder: createSeriesFolder ?? this.createSeriesFolder,
  );
}

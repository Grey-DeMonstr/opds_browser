class CustomSafFolder {
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
  final CustomSafFolder? target;
  final bool createAuthorFolder;
  final bool createSeriesFolder;

  const AppSettings({
    this.target,
    this.createAuthorFolder = false,
    this.createSeriesFolder = false,
  });

  AppSettings copyWith({
    CustomSafFolder? target,
    bool clearTarget = false,
    bool? createAuthorFolder,
    bool? createSeriesFolder,
  }) => AppSettings(
    target: clearTarget ? null : (target ?? this.target),
    createAuthorFolder: createAuthorFolder ?? this.createAuthorFolder,
    createSeriesFolder: createSeriesFolder ?? this.createSeriesFolder,
  );
}

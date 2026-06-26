# Inferred Series from Browse URL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the `series` query parameter from the current browse page URL and use it as an inferred series when `entry.series` is null — for display (italic label) and single-book download folder organisation.

**Architecture:** A pure `inferSeriesFromUrl(Uri)` function feeds an optional `String? inferredSeries` parameter that threads through `buildPathSegments` → `buildFileName` → `BookDownloader.download` → `DownloadNotifier.start` → `_BookEntryTile`. The UI computes the value once per page and passes it down as a constructor param. Inferred series is never stored in `BookEntry`.

**Tech Stack:** Flutter/Dart, flutter_riverpod (Notifier/AsyncNotifier), flutter_test widget tests.

## Global Constraints

- Android only — no iOS code.
- `flutter analyze` must be clean before any commit.
- `flutter test` must pass before any commit (run `dart run tool/check.dart`).
- TDD: write failing test first, then implement.
- All tests run on host — no device/emulator.
- Use PowerShell for all shell commands.

---

### Task 1: `inferSeriesFromUrl` + `inferredSeries` param in `buildPathSegments` / `buildFileName`

**Files:**
- Modify: `lib/domain/download_utils.dart`
- Modify: `test/domain/download_utils_test.dart`

**Interfaces:**
- Produces: `String? inferSeriesFromUrl(Uri url)` — public, exported from `download_utils.dart`
- Produces: `List<String> buildPathSegments(AppSettings settings, BookEntry entry, {String? inferredSeries})`
- Produces: `String buildFileName(BookEntry entry, AcquisitionLink link, AppSettings settings, {String? inferredSeries})`
- All existing call sites are unchanged (named optional param, defaults to null).

- [ ] **Step 1: Write failing tests**

Add to the bottom of the existing `void main()` in `test/domain/download_utils_test.dart`, inside a new group block after the `folderPreferredLink` group:

```dart
// ── inferSeriesFromUrl ─────────────────────────────────────────────────────

group('inferSeriesFromUrl', () {
  test('returns series value when present', () {
    final url = Uri.parse('http://example.com/feed?series=The+Wheel+of+Time');
    expect(inferSeriesFromUrl(url), 'The Wheel of Time');
  });

  test('returns null when series param absent', () {
    final url = Uri.parse('http://example.com/feed?author=Tolkien');
    expect(inferSeriesFromUrl(url), isNull);
  });

  test('returns null when series param is empty string', () {
    final url = Uri.parse('http://example.com/feed?series=');
    expect(inferSeriesFromUrl(url), isNull);
  });

  test('returns null for URL with no query params', () {
    final url = Uri.parse('http://example.com/feed');
    expect(inferSeriesFromUrl(url), isNull);
  });

  test('decodes percent-encoded characters', () {
    // series=%D0%92%D0%BE%D0%B9%D0%BD%D0%B0 → "Война"
    final url = Uri.parse(
        'http://example.com/feed?series=%D0%92%D0%BE%D0%B9%D0%BD%D0%B0');
    expect(inferSeriesFromUrl(url), 'Война');
  });
});
```

Add inside the existing `buildPathSegments` group in the same file:

```dart
test('series flag on, entry.series null, inferredSeries provided — inferred series folder created', () {
  const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
  expect(
    buildPathSegments(s, _book(), inferredSeries: 'Inferred Series'),
    ['Inferred Series'],
  );
});

test('series flag on — real entry.series takes precedence over inferredSeries', () {
  const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
  expect(
    buildPathSegments(s, _book(series: 'Real Series'), inferredSeries: 'Inferred Series'),
    ['Real Series'],
  );
});

test('series flag on, entry.series null, inferredSeries null — no folder', () {
  const s = AppSettings(target: SystemDownloads(), createSeriesFolder: true);
  expect(buildPathSegments(s, _book(), inferredSeries: null), isEmpty);
});
```

Add inside the existing `buildFileName` group in the same file:

```dart
test('entry.series null, inferredSeries provided, series folder off — inferred series in filename', () {
  expect(
    buildFileName(_book(), _link('FB2'), _noFolders, inferredSeries: 'Inferred Series'),
    'Jane Doe - Inferred Series - Book Title.fb2',
  );
});

test('entry.series null, inferredSeries provided, series folder on — series omitted from filename', () {
  expect(
    buildFileName(_book(), _link('FB2'), _seriesFolder, inferredSeries: 'Inferred Series'),
    'Jane Doe - Book Title.fb2',
  );
});

test('entry.series set — real series used in filename, inferredSeries ignored', () {
  final book = _book(series: 'Real Series');
  expect(
    buildFileName(book, _link('FB2'), _noFolders, inferredSeries: 'Inferred Series'),
    'Jane Doe - Real Series - Book Title.fb2',
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
flutter test test/domain/download_utils_test.dart
```

Expected: FAIL — `inferSeriesFromUrl` not found; `buildPathSegments` and `buildFileName` don't accept `inferredSeries`.

- [ ] **Step 3: Implement `inferSeriesFromUrl` and update the two functions**

In `lib/domain/download_utils.dart`, add after the `folderPreferredLink` function:

```dart
/// Extracts the `series` query parameter from [url] as the inferred series
/// name, or null when the parameter is absent or empty.
String? inferSeriesFromUrl(Uri url) {
  final value = url.queryParameters['series'];
  return (value != null && value.isNotEmpty) ? value : null;
}
```

Update `buildFileName` signature and body (replace the existing function):

```dart
String buildFileName(
  BookEntry entry,
  AcquisitionLink link,
  AppSettings settings, {
  String? inferredSeries,
}) {
  final parts = <String>[];
  final authors = _authorString(entry.authors);
  if (authors != null && !settings.createAuthorFolder) parts.add(authors);
  final effectiveSeries = entry.series ?? inferredSeries;
  if (effectiveSeries != null && !settings.createSeriesFolder) {
    final idx = entry.seriesIndex;
    parts.add(idx != null
        ? '$effectiveSeries #${_formatIndex(idx)}'
        : effectiveSeries);
  }
  parts.add(entry.title);
  final ext = _formatExt(link.formatLabel);
  var name = _sanitize('${parts.join(' - ')}.$ext');
  if (name.length > 200) {
    final suffix = '.$ext';
    name = '${name.substring(0, 200 - suffix.length)}$suffix';
  }
  return name;
}
```

Update `buildPathSegments` signature and body (replace the existing function):

```dart
List<String> buildPathSegments(
  AppSettings settings,
  BookEntry entry, {
  String? inferredSeries,
}) {
  final segments = <String>[];
  final authors = _authorString(entry.authors);
  if (settings.createAuthorFolder && authors != null) {
    segments.add(_sanitize(authors));
  }
  final effectiveSeries = entry.series ?? inferredSeries;
  if (settings.createSeriesFolder && effectiveSeries != null) {
    segments.add(_sanitize(effectiveSeries));
  }
  return segments;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
dart run tool/check.dart
```

Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/domain/download_utils.dart test/domain/download_utils_test.dart
git commit -m "feat: add inferSeriesFromUrl and inferredSeries support in path/filename builders"
```

---

### Task 2: Thread `inferredSeries` through `BookDownloader.download()`

**Files:**
- Modify: `lib/data/book_downloader.dart`
- Modify: `test/data/book_downloader_test.dart`

**Interfaces:**
- Consumes: `buildPathSegments(..., {String? inferredSeries})` and `buildFileName(..., {String? inferredSeries})` from Task 1
- Produces: `Future<String> BookDownloader.download(BookEntry entry, AcquisitionLink link, AppSettings settings, {String? inferredSeries})`

- [ ] **Step 1: Write the failing test**

Add to `void main()` in `test/data/book_downloader_test.dart`:

```dart
test('inferred series used for path segments when entry.series is null and createSeriesFolder is true', () async {
  final client = MockClient((_) async => http.Response.bytes([1], 200));
  final storage = FakeDownloadStorage();
  final downloader = BookDownloader(client, storage);
  const settings = AppSettings(
    target: SystemDownloads(),
    createSeriesFolder: true,
  );

  await downloader.download(_book, _link, settings, inferredSeries: 'My Series');

  expect(storage.writtenSegments, ['My Series']);
});
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
flutter test test/data/book_downloader_test.dart
```

Expected: FAIL — `download` does not accept `inferredSeries`.

- [ ] **Step 3: Update `BookDownloader.download()`**

Replace the `download` method in `lib/data/book_downloader.dart`:

```dart
Future<String> download(
  BookEntry entry,
  AcquisitionLink link,
  AppSettings settings, {
  String? inferredSeries,
}) async {
  final segments = buildPathSegments(settings, entry, inferredSeries: inferredSeries);
  final fileName = buildFileName(entry, link, settings, inferredSeries: inferredSeries);

  if (await _storage.exists(segments, fileName)) {
    return _alreadyExists;
  }

  late http.StreamedResponse response;
  try {
    final request = http.Request('GET', link.url)
      ..headers['User-Agent'] = 'OpdsBrowser/1.0';
    response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
  } on SocketException catch (e) {
    throw NetworkException(e.message);
  } on TimeoutException {
    throw const NetworkException('Connection timed out');
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpStatusException(
      response.statusCode,
      'HTTP ${response.statusCode}',
    );
  }

  return _storage.write(segments, fileName, response.stream, link.mimeType);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
dart run tool/check.dart
```

Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/book_downloader.dart test/data/book_downloader_test.dart
git commit -m "feat: thread inferredSeries through BookDownloader.download()"
```

---

### Task 3: Thread `inferredSeries` through `DownloadNotifier.start()`

**Files:**
- Modify: `lib/ui/providers.dart`
- Modify: `test/ui/download_notifier_test.dart`

**Interfaces:**
- Consumes: `BookDownloader.download(..., {String? inferredSeries})` from Task 2
- Consumes: `buildFileName(..., {String? inferredSeries})` from Task 1
- Produces: `Future<void> DownloadNotifier.start(BookEntry entry, AppSettings settings, {String? inferredSeries})`

- [ ] **Step 1: Write the failing test**

First, update `FakeDownloadStorage` in `test/ui/download_notifier_test.dart` to capture `writtenSegments` (add one field and one assignment):

```dart
class FakeDownloadStorage implements DownloadStorage {
  final bool existsResult;
  final String writeResult;
  String? writtenMimeType;
  List<String>? writtenSegments;  // add this field

  FakeDownloadStorage({
    this.existsResult = false,
    this.writeResult = 'content://fake/1',
  });

  @override
  Future<bool> exists(List<String> p, String f) async => existsResult;

  @override
  Future<String> write(
      List<String> p, String f, Stream<List<int>> b, String mimeType) async {
    writtenMimeType = mimeType;
    writtenSegments = p;           // add this assignment
    await b.drain<void>();
    return writeResult;
  }
}
```

Update `_makeContainer` to accept an optional `FakeDownloadStorage` instance so tests can inspect it after the call:

```dart
ProviderContainer _makeContainer({
  required MockClient client,
  FakeDownloadStorage? storage,
  bool storageExists = false,
  String storageWriteResult = 'content://fake/1',
}) {
  final s = storage ??
      FakeDownloadStorage(
        existsResult: storageExists,
        writeResult: storageWriteResult,
      );
  final c = ProviderContainer(overrides: [
    httpClientProvider.overrideWith((ref) => client),
    downloadStorageProvider.overrideWith((ref) => s),
  ]);
  addTearDown(c.dispose);
  return c;
}
```

Add the new test to `void main()`:

```dart
test('start() with inferredSeries — inferred series used for path segments when createSeriesFolder is true', () async {
  final storage = FakeDownloadStorage(writeResult: 'content://result');
  final c = _makeContainer(
    client: MockClient((_) async => http.Response.bytes([1], 200)),
    storage: storage,
  );
  const settings = AppSettings(
    target: SystemDownloads(),
    createSeriesFolder: true,
  );

  await c
      .read(downloadNotifierProvider(_linkUrl).notifier)
      .start(_book, settings, inferredSeries: 'My Series');

  expect(storage.writtenSegments, ['My Series']);
});
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
flutter test test/ui/download_notifier_test.dart
```

Expected: FAIL — `start` does not accept `inferredSeries`.

- [ ] **Step 3: Update `DownloadNotifier.start()` in `lib/ui/providers.dart`**

Replace the `start` method inside `class DownloadNotifier`:

```dart
Future<void> start(
  BookEntry entry,
  AppSettings settings, {
  String? inferredSeries,
}) async {
  if (state is DownloadInProgress) return;
  state = const DownloadInProgress();

  final downloader = ref.read(bookDownloaderProvider);
  if (downloader == null) {
    state = const DownloadFailed('Downloads are not supported on this platform.');
    return;
  }

  final link = entry.acquisitionLinks.firstWhere((l) => l.url == _linkUrl);
  final fileName = buildFileName(entry, link, settings, inferredSeries: inferredSeries);

  try {
    final result = await downloader.download(
      entry,
      link,
      settings,
      inferredSeries: inferredSeries,
    );
    final done = result == 'already_exists'
        ? DownloadDone(
            contentUri: '',
            fileName: fileName,
            alreadyExisted: true,
            mimeType: link.mimeType,
          )
        : DownloadDone(
            contentUri: result,
            fileName: fileName,
            alreadyExisted: false,
            mimeType: link.mimeType,
          );
    ref.read<_LastDownloadResultNotifier>(lastDownloadResultProvider.notifier).set(done);
    state = done;
  } on OpdsException catch (e) {
    state = DownloadFailed(_mapError(e));
  } catch (e) {
    state = DownloadFailed('Unexpected error: $e');
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
dart run tool/check.dart
```

Expected: all tests pass, analyzer clean.

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/providers.dart test/ui/download_notifier_test.dart
git commit -m "feat: thread inferredSeries through DownloadNotifier.start()"
```

---

### Task 4: Browse screen — compute, display (italic), and download wiring

**Files:**
- Modify: `lib/ui/browse_screen.dart`
- Modify: `test/ui/browse_screen_test.dart`

**Interfaces:**
- Consumes: `inferSeriesFromUrl(Uri)` from Task 1
- Consumes: `DownloadNotifier.start(..., {String? inferredSeries})` from Task 3

- [ ] **Step 1: Write failing tests**

Add to `void main()` in `test/ui/browse_screen_test.dart`:

```dart
testWidgets('book with no series shows inferred series in italics when URL has series param',
    (tester) async {
  final seriesUrl = Uri.parse('http://example.com/feed?series=Dune+Chronicles');
  final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
  await tester.pumpWidget(buildApp(feed: feed, url: seriesUrl));
  await tester.pumpAndSettle();

  final textWidget = tester.widget<Text>(find.text('Dune Chronicles'));
  expect(textWidget.style?.fontStyle, FontStyle.italic);
});

testWidgets('book with own series uses real series — not italic, URL series ignored',
    (tester) async {
  final seriesUrl = Uri.parse('http://example.com/feed?series=URL+Series');
  final feed = makeFeed(
      entries: [bookEntry(title: 'Dune', series: 'Real Series', seriesIndex: 1)]);
  await tester.pumpWidget(buildApp(feed: feed, url: seriesUrl));
  await tester.pumpAndSettle();

  expect(find.text('Real Series #1'), findsOneWidget);
  expect(find.text('URL Series'), findsNothing);
  final textWidget = tester.widget<Text>(find.text('Real Series #1'));
  expect(textWidget.style?.fontStyle, isNot(FontStyle.italic));
});

testWidgets('book with no series and no URL series param shows empty series area',
    (tester) async {
  final feed = makeFeed(entries: [bookEntry(title: 'Dune')]);
  await tester.pumpWidget(buildApp(feed: feed));
  await tester.pumpAndSettle();

  expect(find.text('Dune'), findsOneWidget);
  // No unexpected series text visible
  expect(find.text('Dune Chronicles'), findsNothing);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
flutter test test/ui/browse_screen_test.dart
```

Expected: FAIL — `inferSeriesFromUrl` not imported; `_BookEntryTile` has no `inferredSeries` param.

- [ ] **Step 3: Update `_BrowseContent.build()` to compute and pass `inferredSeries`**

In `lib/ui/browse_screen.dart` (the `download_utils.dart` import is already present at line 10).

In `_BrowseContent.build()`, add one line after the existing local variable declarations at the top of the method, and pass `inferredSeries` to `_BookEntryTile`:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final (catalogId, url) = args;
  final entries = state.feed.feed.entries;
  final jobState = ref.watch(folderDownloadProvider);
  final inferredSeries = inferSeriesFromUrl(url);   // add this line

  // ... existing ref.listen block unchanged ...

  // In the SliverList delegate, update the BookEntry case:
  BookEntry e => _BookEntryTile(
    entry: e,
    inferredSeries: inferredSeries,   // add this param
    key: ValueKey(e.title),
  ),
```

- [ ] **Step 4: Update `_BookEntryTile` to accept `inferredSeries` and display in italics**

Update the widget class, state, and build method. Replace `_BookEntryTile` and `_BookEntryTileState` entirely:

```dart
class _BookEntryTile extends ConsumerStatefulWidget {
  final BookEntry entry;
  final String? inferredSeries;

  const _BookEntryTile({
    required this.entry,
    this.inferredSeries,
    super.key,
  });

  @override
  ConsumerState<_BookEntryTile> createState() => _BookEntryTileState();
}

class _BookEntryTileState extends ConsumerState<_BookEntryTile> {
  Uri? _downloadUrl;

  Uri get _defaultWatchUrl =>
      (preferredLink(widget.entry.acquisitionLinks) ??
              widget.entry.acquisitionLinks.first)
          .url;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final authors = entry.authors.join(', ');
    final effectiveSeries = entry.series ?? widget.inferredSeries;
    final isInferredSeries = entry.series == null && effectiveSeries != null;
    final seriesText = effectiveSeries != null
        ? (entry.seriesIndex != null
              ? '$effectiveSeries #${_formatSeriesIndex(entry.seriesIndex!)}'
              : effectiveSeries)
        : null;

    final hasLinks = entry.acquisitionLinks.isNotEmpty;
    DownloadState? downloadState;
    if (hasLinks) {
      final watchUrl = _downloadUrl ?? _defaultWatchUrl;
      downloadState = ref.watch(downloadNotifierProvider(watchUrl));
      ref.listen(downloadNotifierProvider(watchUrl), (_, state) {
        if (state is DownloadFailed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: ${state.message}')),
          );
        }
      });
    }
    final isDownloading = downloadState is DownloadInProgress;

    return ListTile(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => BookDetailsSheet(entry: entry),
      ),
      leading: SizedBox(
        width: 56,
        height: 80,
        child: entry.coverUrl != null
            ? CachedNetworkImage(
                imageUrl: entry.coverUrl!.toString(),
                fit: BoxFit.cover,
                placeholder: (_, _) => const Icon(Icons.book),
                errorWidget: (_, _, _) => const Icon(Icons.book),
              )
            : const Icon(Icons.book),
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (authors.isNotEmpty) Text(authors),
          Text(
            seriesText ?? '',
            style: isInferredSeries
                ? const TextStyle(fontStyle: FontStyle.italic)
                : null,
          ),
        ],
      ),
      isThreeLine: authors.isNotEmpty,
      trailing: hasLinks
          ? isDownloading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _onDownloadTap(context),
                )
          : null,
    );
  }

  Future<void> _onDownloadTap(BuildContext context) async {
    final entry = widget.entry;
    final settings = ref.read(settingsProvider).value ??
        const AppSettings(target: SystemDownloads());
    final preferred = preferredLink(entry.acquisitionLinks);
    if (preferred != null) {
      setState(() => _downloadUrl = preferred.url);
      ref
          .read(downloadNotifierProvider(preferred.url).notifier)
          .start(entry, settings, inferredSeries: widget.inferredSeries);
    } else {
      final chosen =
          await _showFormatPicker(context, entry.acquisitionLinks);
      if (chosen == null || !mounted) return;
      setState(() => _downloadUrl = chosen.url);
      ref
          .read(downloadNotifierProvider(chosen.url).notifier)
          .start(entry, settings, inferredSeries: widget.inferredSeries);
    }
  }

  Future<AcquisitionLink?> _showFormatPicker(
    BuildContext context,
    List<AcquisitionLink> links,
  ) {
    return showDialog<AcquisitionLink>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: links
              .map(
                (l) => TextButton(
                  onPressed: () => Navigator.of(ctx).pop(l),
                  child: Text(l.formatLabel),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```powershell
dart run tool/check.dart
```

Expected: all tests pass, analyzer clean.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/browse_screen.dart test/ui/browse_screen_test.dart
git commit -m "feat: display and use inferred series from URL in browse screen"
```

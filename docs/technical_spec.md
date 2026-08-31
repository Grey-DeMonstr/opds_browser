# OPDS Browser — Technical Specification

**Last reviewed:** 2026-08-31

The architectural decisions and invariants new work must respect. It is not a
description of the current code — read the code for that. What is written here is
what the code cannot tell you: why a seam exists, what breaks if it is crossed,
and which rules are load-bearing rather than incidental.

For what the app does, see [functional_spec.md](functional_spec.md).

---

## 1. Layering

```
domain/  entities, value objects, interfaces, pure functions
data/    implementations — OPDS client, DAOs, storage, downloads
ui/      screens, widgets, Riverpod providers
```

Three rules:

1. **`domain/` and `data/` stay pure Dart.** No Flutter bindings, so both are
   testable without a Flutter environment. `dart:io` in `data/` is the only
   concession.
2. **`domain/` depends outward on nothing.** Interfaces are declared there,
   implementations live in `data/`, and `ui/` wires them together through
   providers. A `domain/` file importing `data/` or `ui/` is a defect.
3. **Logic that can be a pure function must be one.** Anything decided by rules
   rather than I/O — classification, filtering, naming, validation, format
   preference — belongs in `domain/` as a free function with its own tests. This
   is what keeps the widget tests thin and the rules verifiable in isolation.

The analyzer runs `flutter_lints` plus `strict-casts`, `strict-raw-types` and
`strict-inference`, and must stay clean.

### 1.1 Technology choices — do not substitute

| Concern | Package | Why it is fixed |
|---|---|---|
| State | `flutter_riverpod` | Plain `Notifier`/`AsyncNotifier`. No codegen — do not introduce it |
| Navigation | `go_router` | |
| HTTP | `http` | Deliberately minimal; not dio |
| Feed XML | `xml` | |
| Entry descriptions | `html` | Descriptions are **not** well-formed XML — bare `<br>`, `<p>` inside `<p>`, stray FB2 tags. `xml` cannot parse them, so the two parsers are not interchangeable |
| Local DB | `sqflite` | Raw SQL, thin DAOs. `sqflite_common_ffi` for host tests and the desktop build |
| Settings | `shared_preferences` | |
| Storage | `saf_stream` + `saf_util` | SAF only — see §5 |
| FB2 archives | `archive` | |

---

## 2. Protocol abstraction

OPDS 1.x is the only protocol implemented. **The seam for adding OPDS 2.0 already
exists and must be kept usable**: caching, downloads and UI depend on a
protocol-neutral model, never on Atom.

```dart
abstract interface class OpdsClient {
  Future<ParsedFeed> fetchFeed(Uri url);   // never touches the cache
  Future<bool> probe(Uri url);
}
```

`probe` returns false when the URL is reachable but is not a feed this client
understands, and lets `NetworkException` / `HttpStatusException` propagate. That
distinction is what lets the add-catalogue dialog separate "not a catalogue" from
"could not reach it" (functional §4.1) — a `probe` that swallowed transport errors
would make the two indistinguishable.

Adding a protocol means a new `OpdsClient` implementation and protocol detection
at catalogue-add time. It must not require changes to `FeedRepository`, the cache
schema, the download pipeline or any screen. If it does, the abstraction has been
breached somewhere and that is the bug to fix first.

### 2.1 The neutral model contract

`ParsedFeed`, `NavigationEntry`, `BookEntry`, `AcquisitionLink` in
`domain/models.dart`. Any client, for any protocol, produces these and nothing
else.

**Every type must stay JSON-serializable in both directions.** The cache stores
feeds as JSON (§4), so a field that cannot round-trip cannot exist. Codecs omit
null and empty values, and `FeedEntry.fromJson` dispatches on a `type`
discriminator.

Four fields are load-bearing in ways their names do not reveal:

- **`NavigationEntry.linkType`** — the declared link `type`, verbatim. It is the
  *only* signal distinguishing a real folder (`kind=navigation`) from a page that
  merely wraps books (`kind=acquisition`). Titles and subtitles are no guide:
  catalogues publish series folders subtitled "1 книга по автору" that really are
  folders, and single-book pages with no count at all. Any future heuristic about
  folder contents reads this field, not the text.
- **`BookEntry.contentHtml`** — the description as the feed's own markup, stored
  **unparsed**. Only the book page needs structure, and splitting every entry of a
  200-book feed up front is wasted work. Parse it at the point of display, once.
- **`BookEntry.summary`** — the same description, tags stripped. List rows need
  text, not structure. Keep both; deriving one from the other at render time
  reintroduces the cost that separating them avoided.
- **`ParsedFeed.searchLinks`** — every feed-level `rel="search"`, verbatim, with
  the declared `type`. Empty means two different things the model deliberately
  does not distinguish: a catalogue that advertises no search, and a row cached
  before the field existed. The schema bump in §4 is what keeps the second case
  from happening.

`CachedFeed` carries `fetchedAt` and `fromCache`. **`fromCache` is not
diagnostic** — the single-book probe walk uses it to decide whether it owes the
catalogue a pause (§6.4). Anything that fabricates or ignores it will make the app
rude.

---

## 3. Parsing contracts

A client for any protocol classifies entries the same way, in this order:

1. Any acquisition link (`rel` starting `http://opds-spec.org/acquisition`) → book.
2. Otherwise a link to another feed → folder.
3. Otherwise the entry is dropped silently.

Other standing constraints:

- **Be lenient.** Real catalogues are sloppy. A malformed entry is dropped; a
  malformed document is a `ParseException`. Neither aborts anything above it.
- **Non-UTF-8 encodings must keep working.** `windows-1251` in particular —
  Russian catalogues depend on it, and it is handled with a built-in table rather
  than a dependency. Decode bytes before parsing; do not hand a pre-decoded string
  to a parser.
- **Resolve every href against the feed's effective base,** with `xml:base` taking
  precedence over the request URL.
- **Series extraction stays one function.** Sources are tried in order and the
  first match wins. New catalogue conventions are added there, with fixtures — not
  inline at a call site.

### 3.1 Search links, and how a query becomes a URL

Finding the search URL is a three-step rule, ordered by what each step costs:

1. **The feed's own templated link.** A `rel="search"` whose href already carries
   `{searchTerms}` is the template. Substitute and fetch — no extra round trip.
2. **The description document.** A `rel="search"` typed
   `application/opensearchdescription+xml` points at an OpenSearch description;
   fetch it once per catalogue and read its `<Url template>`. A document may list
   several, one per output type, and a browser-facing `text/html` one is often
   listed first — prefer an Atom one, because the feed parser cannot read HTML.
3. **Neither.** The catalogue cannot be searched and the app says so. **It must
   never guess a search URL**; a fabricated one produces an error the user cannot
   act on.

`preferredSearchLink` implements the ordering and `parseOpenSearchTemplate`
step 2. Both are pure and tested directly.

**Templates do not survive as `Uri` unexamined.** Resolving an href against the
feed's base yields a `Uri`, and `Uri` normalises `{` and `}` to `%7B` and `%7D`.
Every check and substitution therefore goes through `searchTemplateOf`, which
decodes first. Reading `SearchLink.url` directly and looking for a literal
`{searchTerms}` silently finds nothing — a bug that has already been written once.

**Terms are percent-encoded as UTF-8**, whatever encoding the catalogue serves its
feeds in; `windows-1251` catalogues accept UTF-8 query strings. Every macro other
than `{searchTerms}` is emptied rather than left in place, since the app supplies
none of them and a brace-wrapped name reaching the server as a literal is worse
than a blank.

**A result feed is an ordinary feed** — paginated with `rel="next"`, with no total
count, no relevance order worth trusting, and no way to scope a query to anything
but the whole catalogue. Some catalogues answer a query with a *navigation* feed
of scopes rather than results, so a search result must render both entry kinds.

### 3.2 Format labels are identifiers

The MIME-to-label mapping produces values that are switched on elsewhere:

| MIME type | Label |
|---|---|
| `application/fb2+zip`, `application/x-zip-compressed-fb2` | `FB2.ZIP` |
| `application/fb2`, `application/x-fictionbook+xml` | `FB2` |
| `application/epub+zip` | `EPUB` |
| `application/pdf` | `PDF` |
| `application/x-mobipocket-ebook` | `MOBI` |
| anything else | the subtype, uppercased |

They are **not** display strings that happen to be shown. Supporting a new format
means touching three places together: this mapping, the preference order (§6.1)
and the file extension derivation (§6.2). Changing a label silently changes both
of the others.

---

## 4. Persistence decisions

One sqflite database. Foreign keys on for every connection; deleting a catalogue
cascades to its cached feeds and favourites.

**Cache rows are opaque JSON and do not describe themselves.** This has one
consequence that must be honoured every time: *widening the parsed model requires
a schema version bump whose migration discards the feed cache.* An older row is
missing the new fields and nothing in it says so, so a screen built from one is
quietly wrong rather than visibly broken. Discarding costs a single re-fetch. Do
not attempt to migrate cache rows forward.

**Settings live in `shared_preferences`, not the database.** Absent boolean keys
must read back as the intended default for a fresh install, so changing a default
is a change to the read path — existing installs keep the value they stored.

**Default catalogues seed on database creation only.** A user who deleted a
default must not see it return after an update. New defaults therefore reach
existing installs never; if that is ever wanted, it needs a deliberate one-shot
migration, not a change to seeding. Tests construct the database with seeding off.

---

## 5. Storage: a folder is mandatory

There is no system-Downloads path and no fallback location. `AppSettings.target`
is nullable, and **null means "not chosen yet"** — that is what the on-demand
folder request tests for. `copyWith` needs an explicit clear flag, because passing
null cannot express "clear it" as distinct from "leave it".

Two interfaces isolate every platform call:

```dart
abstract interface class DownloadStorage {
  Future<bool> exists(List<String> pathSegments, String fileName);
  Future<String> write(List<String> pathSegments, String fileName,
                       Stream<List<int>> bytes, String mimeType);
}

abstract interface class FileOpener {
  Future<void> open(String uri, String mimeType);
}
```

`write` returns an opaque locator that `FileOpener.open` understands. Callers must
treat it as opaque — never parse it, never assume it is a path. The download
engine depends on these interfaces only, which is what makes it testable with
in-memory fakes; anything reaching around them to SAF directly forfeits that.

**SAF write-back addresses a location, not just a document.** Anything that
rewrites an existing file needs the parent URI alongside the document URI. Carry
both wherever a file is modelled.

**The folder is requested on demand, never at startup**, from one shared gate in
front of every action that needs one. That gate must **await** the settings future
rather than reading a cached value: on a cold start the notifier may still be
loading, and a null there is indistinguishable from a genuinely unset folder. New
actions requiring a folder go through the same gate.

### 5.1 The desktop build

Android is the only shipped platform (§10), but the app also runs on Windows so
that screens can be exercised with hot reload instead of a device. That is what
the second implementation of each storage interface is for: SAF on Android, plain
`dart:io` and `file_selector` elsewhere, chosen behind `Platform.isAndroid` in the
providers. The desktop build is a development convenience and carries no promises;
keep the branch inside the providers so no screen or domain rule learns about it,
and add the desktop half whenever a new platform interface appears.

---

## 6. Download rules

### 6.1 Two preference functions, deliberately different

- **`preferredLink`** returns null when a choice is genuinely needed, which is the
  caller's signal to show a picker.
- **`folderPreferredLink`** never returns null; it falls through to a full
  priority order and finally the first listed link.

The split is the design, not an oversight: unattended contexts — the folder job,
and the book page's named action button — must never need a human, while a browse
row's terse download button can afford to ask. Do not collapse them into one
function with a flag.

### 6.2 Naming and placement are complementary

`buildFileName` and `buildPathSegments` partition the same information: a segment
one emits is a segment the other omits. Turning a folder option on **moves**
information, it never duplicates it. Both take the effective series as the book's
own falling back to the series inferred from the URL, so an inferred series names
files exactly as a declared one would. Any change to either must keep the pair
complementary, and both are covered by the heaviest tests in the domain layer.

The user-visible naming rules are in functional §10 — that is the specification;
these functions implement it.

### 6.3 Nothing is ever overwritten

A destination that already exists short-circuits before any request is made and
reports itself through a distinct outcome, separate from both success and failure.
Three behaviours rest on that third outcome: the "already downloaded" message, the
folder job's skipped count, and folder downloads being resumable after an
interruption. A change that folds it into success or failure breaks all three.

### 6.4 Politeness is a constraint, not a tuning knob

Most catalogues serve one request per address at a time and object to bursts.
Therefore:

- Book downloads in a folder job run **sequentially**, with a pause between them.
- Search pages are fetched **one at a time**, with a pause between them.
- Background probes run **one at a time**, with a pause between them, and skip the
  pause after a cache hit — a hit cost the catalogue nothing, so nothing is owed.
- Every such delay is injected, so tests can drive it to zero. **Tests are the
  only reason to shorten one.**

Concurrency here is not a performance win waiting to be claimed. Raising it is a
behavioural change against third-party servers and needs a deliberate decision.

---

## 7. Caching policy

- **Cache forever.** A hit is returned whatever its age. Opening a folder again,
  and every backward navigation, must cost zero network traffic.
- **Keys are normalised URLs.** One pure normalisation function serves the cache
  key, the folder scan's cycle detection and the is-this-the-root test that places
  the Search row; they must not drift apart.
- **Pagination is merged before caching.** Following the feed's next-page links
  and storing one merged row is what makes "a folder" the unit the user and the
  folder scan both work in. A cached row is a complete folder with no continuation.
- **Merging is bounded** by a page count and an entry count, and stores what it
  collected when a bound is hit. An unbounded merge against a large catalogue is a
  hang.
- **Search results are not cached at all.** They are a query's answer, not a
  folder, and they have no stable URL to key on.

Background work that mutates a loaded feed — the single-book probe walk is the
current example — must carry a **generation counter**. Anything in flight over a
superseded entry list stops writing into the new one. Any future background
enrichment of a listing needs the same guard.

---

## 8. Folder download job

Two phases over one state machine: scan to a tree, then download a selected
subtree. The separation exists so the user chooses before anything is fetched.

Constraints the implementation must keep:

- **Scanning goes through the feed repository**, so already-browsed subtrees cost
  nothing.
- **Cycle protection** by normalised URL. Catalogues do link in circles.
- **Bounded** by depth, folder count and book count. Hitting a bound flags the
  result and stops that branch; it never aborts the job or throws away what was
  collected.
- **The scanned tree is collapsed** — single-child folders fold into their child,
  empty folders are pruned — so selection shows structure rather than corridors.
- **Selection folds books by title within a folder.** Large catalogues list one
  title many times over, once per scan, uploader or format. A checkbox means "this
  book", not "this listing". Selection state is the set of acquisition links a row
  stands for.
- **One failure never aborts the run.** Cancellation stops after the item in
  flight.
- **Progress is reported through a callback and the download function is
  injectable**, so the job is testable end to end without network or storage.

**Lifecycle.** Abandoning the flow must reset the state machine, not merely cancel
it. A cancel alone lets the scan complete into a terminal state with no screen left
to clear it, which wedges the entry point off permanently. Any new exit path from
these screens has the same hazard.

There is no background service: a job does not survive leaving the app. Changing
that is a significant piece of work, not a small one.

---

## 9. Local library

Reads and writes the user's folder directly rather than the catalogue. The feature
is still in development (functional §11); the structure below is what it must keep
as it grows.

**The folder convention is the specification.** With per-author and per-series
folders on, a book's path is a claim about its metadata; the library exists to
detect and settle disagreements between the two. The convention itself is in
functional §11 — validation and fixing implement it and must agree with each other
exactly.

- **Validation is pure.** It takes a tree, returns an annotated tree, performs no
  I/O. This is what makes the convention testable without an FB2 round-trip, and
  it must stay that way.
- **Fixing is a separate orchestrator** that walks an already-annotated tree and
  performs the writes. Rule and effect stay apart.
- **Fixing derives author and series from the path. It never derives the title.**
  A path says where a book was filed, not what it is called.
- **Scanning streams results** so the UI can report progress during a long walk.
- **A parse failure is never fatal.** The book keeps its filename as a title, and
  that fallback is cached so the file is not re-read on every visit.
- **Parsed metadata is cached, keyed by relative path**, and refresh clears it
  wholesale.
- **Both plain and zipped FB2 must round-trip.** Writing metadata back means the
  correction travels with the file to any other reader — that is the point of the
  feature.

---

## 10. UI architecture

- **Riverpod, plain notifiers, no codegen.** Providers are `family`-keyed where
  instances must not share state — per-folder browse state, per-URL download state.
- **The navigation stack is the folder depth.** One browse route instance per
  folder. Context about how a folder was reached (the tapped entry's title and
  subtitle) and the inherited series travel as query parameters, because the
  destination cannot recover them from the feed.
- **Cross-screen announcements belong above the navigator.** A completion notice
  attached per screen fires once per stacked level; dismissing one only brings up
  the next. Anything announcing the result of work that outlives a single screen
  goes at the router level.
- **Presentation tokens Material does not name** — hairlines, dim text, bucket
  labels, accent fills — come from one theme extension, not from literals at call
  sites. Both light and dark themes must be kept in step.
- **Shared row shapes live in `ui/widgets/`, not in a screen.** A catalogue root
  and the home screen draw the same marked row; the levels below draw the plain
  entry row. A screen that grows its own copy is how the two drift apart.

---

## 11. Testing and the quality gate

**Test-first.** Write the failing test, then the implementation.

- **Everything runs on the host** with `flutter test`. No emulator, no device, no
  `integration_test`. A design that cannot be tested that way needs reconsidering
  before it needs an exception.
- **Fixtures are committed and real-world-shaped**, including the ugly cases:
  malformed XML, non-UTF-8 encodings, relative hrefs with `xml:base`, paginated
  feeds, entries with and without series, books with and without FB2. A new
  parsing rule arrives with the fixture that motivated it.
- **Pure functions are unit-tested directly.** That is the payoff for rule 3 in §1.
- **Repository tests run real SQL** through `sqflite_common_ffi`, including
  migrations and cascade behaviour.
- **Widget tests use provider overrides with fakes** — never real network or
  database.
- **No private data in the repository.** `tool/check_privacy.dart` rejects any
  hostname, IP address or absolute path not on the allow-list it carries; an
  allow-list on purpose, since a deny-list would have to name the very strings we
  keep out. New tests should use the RFC 2606 reserved names and RFC 5737
  documentation addresses, which need no entry. Its rules are unit-tested and run
  on CI; the sweep over the working tree runs only locally, being a pre-commit
  concern.
- **`dart run tool/check.dart` (`make check`) is the gate**: analyze then test,
  both clean, before any task is complete.

---

## 12. Platform and release

Android only, `minSdk` 29 — the SAF-only storage model is what removes any need
for legacy storage permissions, so lowering it is not a free change.
`applicationId` and `namespace` are `monster.greyde.opds_browser`. The Windows
build (§5.1) is for development and is not released.

CI verifies every push; a `vX.Y.Z` tag cuts a release. **Release notes come from
`changelog.txt`, not from commit subjects** — the release page is read by users —
and the workflow fails when the tagged version has no section there. Design and
rationale:
[superpowers/specs/2026-08-22-android-release-pipeline-design.md](superpowers/specs/2026-08-22-android-release-pipeline-design.md).

---

## 13. Known deviations to close

- The user-facing error wording (functional §12) is applied to single-book
  downloads only. Feed loads and refreshes still surface raw exception text.
  Closing this means routing feed errors through the same mapping — the mapping
  already covers every case.

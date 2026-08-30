# OPDS Browser — Functional Specification

**Describes:** version 0.2.1 · **Last reviewed:** 2026-08-30

What the app does, from the outside. No code appears here — for how any of it is
built, see [technical_spec.md](technical_spec.md).

---

## 1. What the app is

An Android app for browsing open OPDS catalogues and downloading books from them.

There are no accounts, no login, no billing and no DRM. Books are not read inside
the app: a finished download is handed to whichever reader app the device already
has. Everything the app stores lives either in its own database (catalogues,
favourites, the feed cache) or in a folder on the device the user picks once.

### 1.1 What people use it for

1. Registering OPDS catalogues by URL, and editing or deleting them later.
2. Walking a catalogue's folder hierarchy, with instant back-navigation.
3. Searching a whole catalogue, where the catalogue offers a search.
4. Downloading one book, or picking through a whole folder tree and downloading a
   selection of it.
5. Bookmarking any folder as a favourite, reachable in one tap from the home screen.
6. Keeping the downloaded library tidy — checking that files sit in folders matching
   their own metadata, and correcting either side when they do not.

### 1.2 Out of scope

- **OPDS 2.0.** Only OPDS 1.x (Atom/XML) catalogues work. A 2.0-only catalogue fails
  when added.
- **Searching inside a folder.** The protocol has no such notion: a query goes to the
  catalogue as a whole (§5.6). The browse screen's **Filter** narrows the page in front of
  you without asking the server anything (§5.1). There is nothing in between.
- **Authentication.** No HTTP Basic, no OAuth. A catalogue that demands credentials
  reports that it is unsupported.
- **Reading.** No reader, no reading progress, no bookshelf of what you have read.
- **iOS.** Not supported and not planned.
- **Tablet layouts.** One phone-oriented layout.

---

## 2. Concepts

- **Catalogue** — an OPDS source the user registered: a title and a root URL.
- **Folder** — the contents of one catalogue URL. What the user walks through.
- **Folder entry** — a row that opens another folder.
- **Book entry** — a row with at least one downloadable format.
- **Favourite** — a saved pointer to one folder inside one catalogue, listed on the
  home screen.
- **Library folder** — the single folder on the device where downloads are written
  and where the local library is read from.
- **Prefix bucket** — an alphabetic grouping folder a large catalogue synthesises,
  named with a trailing `~` (for example `DIC~`). Scaffolding, not something anyone
  published.

A folder can hold both folder entries and book entries at once, and the list shows
them in the order the catalogue sent them.

---

## 3. First run

A fresh install starts with one catalogue already registered — **Project Gutenberg** —
so there is something to browse before the user adds anything. It can be deleted like
any other, and deleting it is permanent: updates never bring it back.

No folder is requested at startup. The app asks for a library folder the first time an
action actually needs one — downloading a book, downloading a folder, or opening the
local library. The request is a short explanation followed by the system folder picker;
declining it cancels the action that triggered it and nothing else. Once chosen, the
folder is remembered and the app never asks again unless the permission is lost.

---

## 4. Home screen

One scrolling view with two sections.

**Favourites** appears only when there is at least one. Each row names the favourite
and the catalogue it belongs to; tapping opens that folder.

**Catalogues** lists every registered catalogue with its root URL beneath the title.
Tapping opens the catalogue's root folder. Each row has an overflow menu with **Edit**
and **Delete**. With no catalogues at all, the section is replaced by a prompt to add
one.

The app bar carries **Manage local library** and **Settings**. An **Add catalogue**
button floats over the list.

### 4.1 Adding and editing a catalogue

The dialog asks for a **Title** and a **URL**, both required. A URL typed without a
scheme gets `https://` prepended.

On save the app fetches the URL to check it is a readable OPDS 1.x feed. If it is not,
the dialog reports **"Not a supported OPDS catalogue"** and offers **Save anyway**,
which stores it unchecked. A network failure is reported in the dialog rather than
treated as a rejection.

Editing pre-fills both fields. Changing a catalogue's URL keeps the catalogue: any
feeds cached under the old URL simply stop being reachable.

### 4.2 Deleting a catalogue

Deleting asks for confirmation and warns that the catalogue's favourites and cached
feeds go with it. Downloaded files are untouched — they live in the library folder,
not in the app.

---

## 5. Browsing a folder

The list shows the folder's entries in feed order.

**Folder rows** show the title as the catalogue wrote it, with what the catalogue said
is inside on a quieter line beneath — "930 authors", "1 book by this author" — with
the number picked out. Prefix buckets are set in monospace and dimmed, marking them as
scaffolding rather than published entries.

**Book rows** show a cover thumbnail, the title, the authors, and a third line that
carries the series when there is one and the description when there is not. That third
line is often the only thing separating two listings of the same title — Project
Gutenberg publishes stripped and illustrated editions of a book under one name. A
download button sits at the end of the row.

The header names the current folder, and beneath it, the entry that was tapped to get
here together with what that entry claimed to hold. At a catalogue's root there is no
second line.

### 5.1 Filtering

Chips sit above the list, **on a page holding more than five rows** — folders, books or
both. Below that the list is short enough to read as it stands and there is nothing for
them to do, so the whole row stays away; a catalogue's root of a handful of sections
carries no chips at all.

The three are:

- **All** — everything the catalogue sent.
- **Entries only** — hides prefix buckets.
- **Filter** — opens a field, *"Filter this page"*, that keeps only rows whose title
  contains what is typed, ignoring case.

All of them act on the folder already loaded; none sends anything to the server. The word
is **Filter** rather than Search for that reason: it narrows the rows in front of you and
nothing else, where **Search** (§5.6) leaves the page and asks the catalogue.

The count is taken over everything the catalogue sent, before **All** or **Entries only**
narrows it, so the chips do not appear and vanish as those are switched.

When a filter empties the list, the screen says *"Nothing on this page matches."*; a folder
that is genuinely empty says *"This folder is empty."*

### 5.2 Cached folders and refreshing

**A folder is cached forever.** Once fetched, opening it again renders instantly from
the cache with no spinner and no network traffic, however old the cache is. Walking
back never re-fetches anything.

A folder with no cache entry shows a loading indicator while it is fetched. Fetching
follows the catalogue's paging links and merges every page into one folder, so a
paginated listing arrives as a single list.

**Refresh** — the app-bar button or pull-to-refresh — re-fetches and replaces the
cached copy. The existing content stays on screen behind a thin progress bar while it
runs; if the refresh fails, the cached content stays and the failure is reported in a
snackbar.

### 5.3 Folders that hold a single book

Large catalogues wrap individual books in a folder of their own, so a listing of a
hundred books reads as a hundred folders that each need a tap to reveal one title.

Where the catalogue itself marks a row as leading to books rather than folders, the
app fetches it in the background and, if it turns out to hold exactly one downloadable
book, swaps the row for that book. The listing is usable immediately and the rows
settle behind the reader. Probes are made one at a time with a pause between them,
because most catalogues serve one request per address at a time and object to bursts;
a probe answered from the cache costs nothing and is not paused for. A probe that
fails leaves the folder row alone.

### 5.4 Series taken from the URL

Some catalogues express a series only in the link they publish, never in the book's own
metadata. Where a folder's URL carries a series name, books in that folder inherit it:
the row shows it in italics to mark it as inferred rather than stated, and it is
carried down into sub-folders and used when naming downloaded files.

### 5.5 Debug panel

With debug mode on (see §9), a black strip above the list shows the current URL decoded,
one query parameter per line. Tapping it copies the full URL.

### 5.6 Searching the whole catalogue

**Where it is.** A catalogue's root page opens with a **Search** row — the first row,
accented, subtitled *"Every book in the catalogue · slow"*. It is not a folder the
catalogue published; it is one more way in, so it takes the same shape as the rows beneath
it.

The row appears only on a catalogue's root, and only when that catalogue says it can be
searched. A catalogue that advertises no search simply has no row, rather than a dead one.
Levels below the root have no Search row even though most catalogues repeat the offer on
every page they serve.

**Asking.** The screen opens with the field focused, above one sentence saying what a
query costs: it searches all of the named catalogue, *not the folder you came from*, and
results arrive one page at a time and can take a while. The field asks for a title, author
or series.

**Results.** The header carries the catalogue's name, how many results have arrived, and
which page that took — *"Example · 40 loaded · page 2"*. That is a count of what has
arrived and not a total: the protocol never sends one, and the app does not invent it.

Pages are fetched one at a time with a pause between them, and each lands on screen as it
arrives rather than after the last. While a page is in flight the foot of the list says
so — *"Fetching page 3…"* — with **Stop** beside it, because the wait has no known end.
Stopping keeps everything already found and offers **Continue**; a page that was in flight
when Stop was pressed is discarded rather than half-shown.

Where a catalogue answers in a single page and offers no next one, there is no footer at
all: nothing is fetching and there is nothing to continue to.

**What comes back.** Usually books, listed as they are anywhere else. Some catalogues
answer a query with a menu — *search authors*, *search series*, *search titles* — and
those rows open like any folder, so the search continues by tapping rather than by typing.

A query matching nothing says *"Nothing found for that."* A failure says what went wrong
and offers **Retry**, keeping whatever had already arrived.

---

## 6. The book page

Tapping a book row opens a panel that can be dragged up to fill the screen — some
catalogues pack an entire bibliographic record into a description, so it scrolls rather
than truncating.

It shows the cover, title, authors, series and the catalogue's subject tags, then the
download actions, then the description.

The description is presented one of two ways, decided by its own shape:

- **When the catalogue structured it with headings** — everything above the first
  heading is shown whole as the blurb, and everything from the heading down is folded
  into a **Details** disclosure of labelled facts.
- **When it has no headings** — it is shown as one block, clamped to six lines, with
  **Show more** and **Show less**.

---

## 7. Downloading one book

### 7.1 Choosing a format

The book page offers one named action — **Download FB2**, **Download EPUB**, whatever
is best available — with the remaining formats beside it as chips that download
directly. Preference runs **FB2.ZIP** before **FB2**, then **EPUB**, **PDF**, **MOBI**,
and finally whatever the catalogue listed first. The book page never asks; the button
always names a format.

The download button on a browse row is quieter about it. With one format, or with an
FB2 variant available, it downloads without asking. With several formats and no FB2
among them, it opens a format picker first.

### 7.2 While it runs and when it finishes

The row or the button shows a spinner. When the file lands, a message appears wherever
the reader has got to — it is announced once, not once per stacked screen — naming the
file with an **Open** action that hands it to a reader app. If no app can open that
format, that is reported.

A file that is already at the destination is not downloaded again. It is reported as
**"Already downloaded"**, with no Open action, and this is what makes an interrupted
folder download resumable.

A failure is reported with the reason and a **Retry** action.

---

## 8. Downloading a folder

The download-folder action on the browse screen starts a three-step flow. It is
unavailable while another folder job is running.

**Scan.** The app walks the folder and everything beneath it, showing a running count
of folders found and a **Cancel** button. It reuses cached folders, so a subtree already
browsed costs no network traffic. The walk stops at 10 levels deep, 500 folders or 2000
books, whichever comes first; it also refuses to revisit a folder it has already seen,
so a catalogue that links in circles cannot trap it. Leaving this screen abandons the
job.

**Select.** The scan result is presented as cards, one per folder that directly holds
books, with a header giving the group and book counts. The first card is open and the
rest are closed. Inside a card, each title is one row with a checkbox — every listing of
that title in that folder is covered by the one row, so choosing a book means choosing
the book rather than choosing between its copies. Folder checkboxes are tri-state,
reflecting a partial selection beneath them. **All** and **None** chips set the whole
tree; everything starts selected. If the scan hit one of its limits, the screen says so.

**Download.** The selected books are fetched **one at a time**, with a one-second pause
between them, again to stay polite to the catalogue. The tree stays on screen with a
status icon against each book: in progress, done, skipped because the file was already
there, or failed. Tapping a failed book shows the reason. One failure never stops the
run. **Cancel** stops after the book in flight.

The final screen keeps the same tree with its per-book outcomes and notes whether the
run was cancelled or the scan was cut short by a limit. **Close** returns to browsing.

A folder job does not survive leaving the app; there is no background service.

---

## 9. Settings

- **Downloads folder** — names the chosen folder, with **Change…** to pick another.
- **Create a folder per author** — on by default.
- **Create a folder per series** — on by default.
- An example path underneath updates live to show what the two options produce.
- **Version** — the app version and build number. Double-tapping this row toggles
  **debug mode**, which reveals the browse screen's URL panel. The toggle confirms which
  way it went, since the gesture gives no other sign. Debug mode is a user setting, not
  a property of the build.

Changes take effect immediately.

If the permission on the chosen folder is lost — revoked, or the folder removed — the
app says so and asks for a new one rather than silently writing somewhere else.

---

## 10. Where downloaded files go

Files are written inside the library folder, in sub-folders determined by the two
settings, and named to carry whatever the folders do not.

```
<library folder>/[<Author>/][<Series>/]<file name>
```

The file name pattern is `[<Authors> - ][<Series> #<Index> - ]<Title>.<extension>`,
with each part **omitted when the matching folder already carries it**. With both
folder options on — the default — a book lands as:

```
Jane Doe/Great Series/Book Title.fb2
```

With both off, the same book lands flat as:

```
Jane Doe - Great Series #1 - Book Title.fb2
```

Details:

- **Authors** — one author verbatim; two joined with a comma; three or more become the
  first author followed by *et al.*
- **Series** — the book's own, or the series inferred from the URL (§5.4). The index
  drops a trailing `.0`, so 1.0 is `#1` and 1.5 is `#1.5`. A book with no index gets
  the series name alone.
- A folder level is created only when its option is on **and** the data exists. There
  are no "Unknown author" folders — a missing value just skips that level.
- Characters a file system will not take are replaced with `_`, runs of whitespace are
  collapsed, and the whole name is capped at 200 characters, shortening the title
  rather than losing the extension.
- **Nothing is ever overwritten.** A name already in use means the download is skipped
  and reported as already downloaded.

---

## 11. The local library

Reached from the home screen, this reads the library folder directly rather than the
catalogue, and works on the FB2 files in it.

It exists because of the convention in §10: with both folder options on, a book's path
*is* a claim about its metadata. `Jane Doe/Great Series/Book Title.fb2` says the file's
own author is Jane Doe and its series is Great Series. Files acquired elsewhere, or
edited by other tools, often disagree.

**Scan.** Opening the screen walks the folder, reporting a running count of files found,
then reads each book's title, author, series and series index from the file itself.
Results are cached, so later visits are fast; **Refresh** discards the cache and
re-reads everything. A file that cannot be parsed keeps its filename as a title rather
than disappearing.

**Browse.** The result is a collapsible tree mirroring the folders on disk. Folders show
how many books they contain; books show title, author and series.

**Validate.** Checks every book against the convention: a book one level deep must sit
in a folder named for its author and must have no series; a book two levels deep must
sit in `<author>/<series>`; anything at the root or deeper than two levels is wrong.
Names are compared ignoring case and surrounding space. Books that fail are flagged, and
the flag propagates up so a collapsed folder shows that something inside it needs
attention.

**Fix.** Available once a validation has run. It trusts the folders and rewrites the
files: a book in `<author>/` gets that author and has its series cleared; a book in
`<author>/<series>/` gets both. The book's title is never touched. Books that cannot be
placed this way — at the root, or nested too deep — are left alone, and the result
reports how many were fixed and how many were skipped.

**Edit.** Tapping a book opens its title, author, series and series index for editing.
Saving writes the values into the file itself, so the correction travels with the book
to any other reader.

Both Fix and Edit modify FB2 files in place, in `.fb2` and `.fb2.zip` form alike.

---

## 12. Errors the user sees

Download failures are reported in plain language:

| Situation | Message |
|---|---|
| No connection, DNS failure, timeout | "Network error. Check your connection and try again." |
| The file is gone from the server (404) | "The book file was not found on the server (HTTP 404)." |
| The catalogue demands credentials (401/403) | "This catalogue requires authentication, which is not supported." |
| Any other server error | "Server error (HTTP ⟨code⟩)." |
| The response is not a feed | "The server response is not a valid OPDS feed." |
| The URL is not a supported catalogue | "Not a supported OPDS catalogue." |

**Known gap:** this wording currently covers single-book downloads only. A folder that
fails to load, and a refresh that fails, still surface the underlying technical error
text. See [technical_spec.md](technical_spec.md) §13.

---

## 13. Platform and requirements

- **Android 10 (API 29) or newer.** No storage permission dialogs: the app writes only
  inside the folder the user granted it.
- **A reader app** must be installed to open a downloaded book. The app never opens one
  itself.
- Two distribution channels exist, **Google Play** and **GitHub Releases**, signed with
  different keys. They cannot be upgraded across: switching means uninstalling first,
  which clears settings and the feed cache. Downloaded books survive, as they live in
  the library folder.

---

## 14. Not built yet

Recorded so the absences are deliberate rather than forgotten:

- The original spec had the browse header show how old the cached copy is ("Updated:
  3 days ago"). It shows the folder's origin instead; cache age is not surfaced
  anywhere, and there is no way to clear the cache from Settings.
- Feed-loading and refresh errors are not mapped to friendly wording (§12).
- Recursive download of an entire series is known to misbehave.
- Search has no history: recent queries are not kept, so a repeated search is retyped.
- The Filter's empty state does not offer the catalogue-wide search as a way out, because
  Search lives on the catalogue root and a filtered page is usually somewhere below it.
- Search results are not cached. Leaving the screen discards them, and the same query
  asked again is fetched again.
- No translations; the interface is English only.

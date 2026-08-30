---
name: release
description: Use when cutting a release of OPDS Browser - the user asks to release, cut a version, ship a new version, bump the version, or tag and push a release.
---

# Release

## Overview

A release is one commit that raises `version:` in `pubspec.yaml` and adds a
`changelog.txt` entry, one annotated `vX.Y.Z` tag, and a push. Pushing the tag
is what builds and publishes the app, so it happens last and only with the
user's explicit approval.

Development is Windows-native: use **PowerShell**, never Bash.

## Workflow

Create a todo for each step and work through them in order.

### 1. Check the ground

```powershell
git status --short                # must be clean
git rev-parse --abbrev-ref HEAD   # must be master
git describe --tags --abbrev=0    # the previous release tag
```

A dirty tree or a branch other than `master` stops the release - tell the user
and wait.

### 2. Ask for the version

Read the current `version:` from `pubspec.yaml` and list what has landed since
the previous tag:

```powershell
git log --no-merges --format='%h %s%n%b' <previous-tag>..HEAD
```

Then **ask the user which version to cut**, with a suggestion: patch (`0.2.1` ->
`0.2.2`) when everything since the last tag is a fix, minor (`0.2.1` -> `0.3.0`)
when there is anything a user would call a new feature. Never pick the number
silently.

### 3. Draft the changelog entry

Add a new section at the **top** of `changelog.txt`, under the title, in the
existing shape:

```
X.Y.Z

- One user-visible change, in plain language.
- Fixed: one user-visible fix.
```

Blank line between the version number and its bullets, two blank lines between
sections, wrap at 100 characters with a two-space continuation indent, plain
ASCII - no markdown.

**Writing rules:**

- Write what a user of the app would notice, not what the code does. If nobody
  using the app could tell the difference, it does not belong in the file.
- Skip commits entirely: CI, tests, refactors, dependency bumps, spec and doc
  edits, the version bump itself.
- One user-facing change is one bullet even when it took five commits. Five
  unrelated changes in one commit are five bullets.
- No file names, class names, package names, commit prefixes (`feat:`, `fix:`),
  commit hashes, or issue numbers.
- Prefix fixes with `Fixed:`. Everything else is a plain statement of what the
  app now does.
- **Never write a real catalogue URL or a filesystem path.** These are personal
  data. Project Gutenberg is the only URL or catalogue name that may appear.
- Keep it short. A bullet is one or two sentences.

### 4. Show it and wait

Print the drafted entry to the user and **stop for approval**. Apply any edits
they ask for and show it again. Nothing is committed before they approve.

### 5. Bump and verify

Edit only the `X.Y.Z` part of `version:` in `pubspec.yaml`; leave the `+build`
suffix alone (CI overrides the build number with the commit count).

```powershell
dart run tool/check.dart
```

Must be clean before committing.

### 6. Commit and tag

```powershell
git add changelog.txt pubspec.yaml
git commit -m "chore: raise the version to X.Y.Z"
git tag -a vX.Y.Z -m "vX.Y.Z"
```

The tag is local at this point and can still be deleted (`git tag -d vX.Y.Z`).

### 7. Ask, then push

**Ask the user to approve the push.** Once approved:

```powershell
git push origin master
git push origin vX.Y.Z
```

**Order matters.** The release workflow refuses a tag that is not an ancestor of
`origin/master`, so `master` must land first. Pushing the tag starts the signed
build, the GitHub release, and the Play closed-testing upload - all
irreversible.

## Quick reference

| | |
|---|---|
| Changelog file | `changelog.txt`, repo root, newest version at the top |
| Version source of truth | `version:` in `pubspec.yaml`, checked against the tag by `tool/check_version.dart` |
| Quality gate | `dart run tool/check.dart` |
| Tag format | `vX.Y.Z`, annotated |
| Push order | `master` first, then the tag |

## Common mistakes

- **Pushing the tag before master.** The build fails its ancestor check. Push
  `master` first.
- **Committing before the user has seen the changelog.** Draft, show, wait.
- **Copying commit subjects into the changelog.** GitHub already generates its
  release notes from commit subjects; `changelog.txt` exists to say the same
  thing in a user's language.
- **Listing chores.** A version bump, a CI fix or a spec update is not a change
  to the app.
- **Editing the `+build` suffix.** CI sets the build number.
- **Using Bash.** Cygwin cannot resolve `flutter.bat` or `dart.bat`.

---
name: release
description: Publish an Earth Rally release by hand in the maintainer session - tools/release.py tags a commit on main, zips it and makes the GitHub pre-release. Only when the owner runs /release. The usual path needs no /release - a merged PR with a `Release:` line is published by the maintainer itself.
disable-model-invocation: true
argument-hint: <X.Y.Z-alpha> [release name]
---

Release `$ARGUMENTS` of Earth Rally. Read `docs/writing-standard.md` first; it is the rule for every text below.

The usual way to release is a PR that carries the release (see `/merge-request`): the maintainer publishes it
right after the merge, with no `/release`. Use this skill when the owner wants to publish a commit already on main.

1. **Preconditions.** This is the `maintainer` session (the guard hook blocks `tools/release.py` elsewhere). The
   commit to release is on `origin/main` and already holds the release text: the top `CHANGELOG.md` entry in the
   standard's template (`Works with` line, patch 150 words at most, minor 400) and `M.VERSION` in `mod/`. README
   names no version. If they are missing, tell the owner they come in a PR (`/merge-request` with `Release:`); never
   commit them to `main` here.
2. **Check:** `python tools/release.py X.Y.Z-alpha <commit> --check` (commit default `origin/main`). It checks the
   version is the next one after the latest tag, the CHANGELOG entry and word limit, `M.VERSION`, the README and the
   fork's installer, all read from the commit, and prints the release body.
3. **Publish:** `python tools/release.py X.Y.Z-alpha <commit>`. It tags the commit, pushes the tag, builds the zip
   from the tag and creates the GitHub pre-release. It commits nothing and never pushes `main`. If it fails, fix the
   cause and run the same command again: every step already done is skipped.
4. **Report** the release URL.

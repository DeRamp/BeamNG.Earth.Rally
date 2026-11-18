---
name: release
description: Publish an Earth Rally release - tools/release.py tags a commit on main, zips it with the ARA 2026 season and makes the GitHub release (a full release, for BeamNG.Earth's Add-ons page). Only when the owner runs /release.
disable-model-invocation: true
argument-hint: <X.Y.Z-alpha> [release name]
---

Release `$ARGUMENTS` of Earth Rally. Read `docs/writing-standard.md` first; it is the rule for every text below.

1. **Preconditions.** The commit to release is on `origin/main` and already holds the release text: the top `CHANGELOG.md` entry in the
   standard's template (`Works with` line, patch 150 words at most, minor 400) and `M.VERSION` in `mod/`. README
   names no version. If they are missing, add them on a branch and land it on `main` first (see `CLAUDE.md`).
2. **Check:** `python tools/release.py X.Y.Z-alpha <commit> --check` (commit default `origin/main`). It checks the
   version is the next one after the latest tag, the CHANGELOG entry and word limit, `M.VERSION`, the README and the
   fork's installer, all read from the commit, and that the ARA 2026 season folder is there (`--pack PATH`, default
   `Documents\Claude\Rally Files\ARA Nationals 2026`), and prints the release body.
   `python tools/release.py X.Y.Z-alpha HEAD --build-only` builds the zip alone into `dist/` (no tag, nothing pushed)
   to look at first.
3. **Publish:** `python tools/release.py X.Y.Z-alpha <commit>`. It tags the commit, pushes the tag, builds the zip
   from the tag plus the ARA season folder (under `earthRally/import/ARA Nationals 2026/`) and creates the GitHub
   release: a full release, not a pre-release, because BeamNG.Earth's Add-ons page installs only the newest full
   release. The zip is the one asset; nothing else is attached. It commits nothing and never pushes `main`. If it
   fails, fix the cause and run the same command again: every step already done is skipped.
4. **Report** the release URL. The leaderboard helper (`DeRamp/earth-rally-leaderboards`) is released separately:
   `release/earth-rally-leaderboards/README.md` says how.

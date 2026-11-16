---
name: release
description: Cut an Earth Rally release - changelog, version bump, then tools/release.py tags, zips, pushes and publishes the GitHub pre-release. Run by the maintainer session only, right after merging a PR whose body has a `Release:` line, or when the owner runs /release there.
argument-hint: <X.Y.Z-alpha> [release name]
---

Release `$ARGUMENTS` of Earth Rally. Read `docs/writing-standard.md` first; it is the rule for every text below.

The owner approved the maintainer releasing on its own (2026-11-15): no owner OK is needed at any step.

1. **Preconditions.** This is the `maintainer` session (only it may commit and push to `main`; the guard hook blocks
   other sessions). On `main`, clean, up to date with `origin/main`. Everything in the release came through a merged
   PR. The DeRamp fork's latest release (https://github.com/DeRamp/BeamNG.Earth/releases) has an installer
   and the API this release needs. If any is not true, stop, comment on the PR and tell the sender.
2. **CHANGELOG.md:** the entry at the top in the standard's template, `Works with` line included, dated today. The PR
   usually wrote it: check it, and fix any CONFIRMED wording finding from your merge review. Write it if missing.
   Patch 150 words at most, minor 400. Check with `wc -w`.
3. **README.md:** no version number in it (it says Alpha); update **Known issues** if they changed; stay under 600 words (`wc -w README.md`).
4. **Version bump:** grep for the old version (`M.VERSION` in `mod/`, versioned doc names) and update what should move.
5. **Check:** `python tools/release.py X.Y.Z-alpha --check`. It checks the version, main against origin, the
   CHANGELOG entry and word limit, `M.VERSION`, the README and the fork's installer, and prints the release body.
   Fix what it refuses and run it again. Leave the edits unstaged.
6. **Publish:** `python tools/release.py X.Y.Z-alpha`. It commits `X.Y.Z-alpha: <name>` (only tracked edits), tags
   `vX.Y.Z-alpha`, builds the zip, pushes main and the tag in one atomic push, and creates the GitHub pre-release
   (CHANGELOG entry plus the standard's install block, the zip as the only asset). If it fails partway, it says what
   is done: finish the rest by hand with the same commands, never re-run it.
7. **Report** the release URL as a comment on the PR, to the sender, and to the owner here.

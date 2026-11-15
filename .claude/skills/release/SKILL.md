---
name: release
description: Cut an Earth Rally release - changelog, README version line, tag, zip, GitHub pre-release. Only when the owner runs /release.
disable-model-invocation: true
argument-hint: <X.Y.Z-alpha> [release name]
---

Release `$ARGUMENTS` of Earth Rally. Read `docs/writing-standard.md` first; it is the rule for every text below.

1. **Preconditions.** On `main`, clean, up to date with `origin/main`. Everything in the release has been through
   `/handoff`. The DeRamp fork's latest release (https://github.com/DeRamp/BeamNG.Earth/releases) has an installer
   and the API this release needs. If any is not true, stop and tell the owner.
2. **CHANGELOG.md:** new entry at the top in the standard's template, `Works with` line included. Patch 150 words at
   most, minor 400. Check with `wc -w`.
3. **README.md:** no version number in it (it says Alpha); update **Known issues** if they changed; stay under 600 words (`wc -w README.md`).
4. **Version bump:** grep for the old version (`M.VERSION` in `mod/`, versioned doc names) and update what should move.
5. **Show the owner** the CHANGELOG entry and the diff, and wait for OK.
6. **Commit** `X.Y.Z-alpha: <name>`, tag `vX.Y.Z-alpha`, run `python tools/package.py X.Y.Z-alpha`.
7. **Push** `main` and the tag. **GitHub pre-release** with `gh` (it may not be on PATH:
   `"C:\Program Files\GitHub CLI\gh.exe"`): title `Earth Rally X.Y.Z-alpha: <name>`, body = the CHANGELOG entry plus
   the install block from the standard, asset `dist/earth_rally-X.Y.Z-alpha.zip` only, pre-release ticked.
8. Report the release URL.

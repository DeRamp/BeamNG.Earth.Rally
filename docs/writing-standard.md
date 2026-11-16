# Writing standard: README, changelog, releases

Every README change, changelog entry and GitHub release follows this page. It is short on purpose. If something
needs explaining at length, it goes in a doc under `docs/` and the README or release links to it.

Modelled on RLS Career Overhaul, Advanced Steering, BeamMP and BeamNGpy: versions on the first screen, a short
install, one-line bullets, the same release template every time.

## Rules for all three

* **Player-facing only.** Say what changed for someone playing. Leave out how it was built, why the roadmap moved,
  which tests ran, who drove it, and upstream politics. Those belong in `docs/notes-*`, `docs/plan-*` or the commit.
* **One line per bullet**, about 20 words at most. A bold lead-in of 1-4 words is fine: `**Hairpin** calls ...`.
* **No paragraphs of prose** in a changelog or release. One summary sentence at the top, then bullets.
* **Keys and menu items in bold** (**Ctrl + Alt + K**, **Auto recce**). Files, paths and commands in `code`.
* **Link, don't repeat.** A feature with detail behind it gets one bullet and a link to its doc.
* **Absolute links in CHANGELOG entries** (`https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/…`), because the entry is pasted
  into the release body, where relative links break.
* **Drop empty sections.** No "Fixed: none".

## README

Target **400-600 words**. `wc -w README.md` before committing; over 600 means something should move to
`docs/guide.md`. Sections, in this order and no others:

```markdown
# Earth Rally

<one-sentence pitch>

**Alpha · BeamNG.drive <ver> · BeamNG.Earth modding API <ver>+ · auto recce: [DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)**
[Download](…/releases) · [Wiki](…/wiki) · [Changelog](CHANGELOG.md) · [Player guide](docs/guide.md) · [Report a bug](…/issues)

<hero screenshot from docs/media/>

## What it does        5-8 one-line bullets
## Install             3-5 numbered steps; BeamNG.Earth from the fork first; `earth_rally-<version>.zip`;
                      the mods folder; keep it zipped
## Updating            1-3 bullets: delete the old zip, what carries over
## Quick start         3-4 numbered steps to the first stage
## Known issues        5 bullets at most, the ones a player will hit
## Reporting bugs      what to include: versions, log path, the log lines
## Docs                links only
## License             2-3 lines, plus the rally-data note
```

The version line is the only part that changes on every release. The README never names "this version's" notes;
it links to `CHANGELOG.md`.

## No version numbers in public material

README, the wiki and posts say **alpha**, never a version number (the owner, 2026-11-15). Version
numbers stay in the CHANGELOG, tags, release titles, zip names and `M.VERSION`.

## CHANGELOG.md

One entry per release, newest first. Same bullets as the GitHub release, without the install block.

```markdown
## 1.6.0-alpha: on the stage (2026-12-01)

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)
(official 1.6+ works, without the auto recce).

<one sentence: what this release is>

### New
### Changed
### Fixed
### Known issues
```

* **Patch release** (`1.5.1`): **150 words at most**, usually only **Fixed**.
* **Minor release** (`1.6.0`): **400 words at most**. A big minor can split **New** into 2-4 themed `####` groups
  instead, as long as it stays under 400.
* The `Works with` line is on every entry, even when nothing changed.

## GitHub release

* **Tag:** `vX.Y.Z-alpha` on `main`.
* **Title:** `Earth Rally X.Y.Z-alpha: <name>`, the name 2-5 words, lower case (`the co-driver`). A patch can reuse
  its minor's name or describe the fix (`the first stage goes right`).
* **Asset:** `earth_rally-X.Y.Z-alpha.zip` from `python tools/package.py X.Y.Z-alpha`. Nothing else attached.
* **Pre-release** box ticked while we are in alpha.
* **Body:** the CHANGELOG entry, pasted, then this block:

```markdown
---
**Install:**
1. Install BeamNG.Earth from [the DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases), with its installer, as you
   would the official one.
2. Download `earth_rally-X.Y.Z-alpha.zip` below and put it, still zipped, in
   `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`. Delete the old Earth Rally zip first.

[README](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/README.md) · [Player guide](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/guide.md) · [Full changelog](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/CHANGELOG.md)
```

### BeamNG.Earth: the fork, for now

Every release points players at **[the DeRamp fork of BeamNG.Earth](https://github.com/DeRamp/BeamNG.Earth/releases)**.
The fork is BeamNG.Earth with the modding API Earth Rally needs that is not released yet (today: API 1.9,
`api.roadGraph`, `api.areaPlan`, `api.areaAdd`, `api.areaStatus`; [PR #1249](https://github.com/TecnaGamer/BeamNG.Earth/pull/1249)).

The fork link lives in five places:
* README version line and **Install** step 1.
* The `Works with` line of each new CHANGELOG entry.
* Step 1 of the release install block.
* `docs/guide.md`, **The auto recce and BeamNG.Earth**.

Rules:
* **Link the fork's Releases page**, never a branch. Players run an installer; they do not clone or build.
* **Before tagging**, the fork's latest release has an installer and the API this release asks for.
* Its updater points at the fork; upstream's updater would replace it with official.
* **Switch back to official** when an official release reports modding API `KNOWN_API_MINOR` (`earthAdapter.lua`).
* The owner must also have driven an **Auto recce** stage on that official release.
* Then put the official link in the five places, add a **Changed** bullet telling fork players, and drop this section.

There is no separate `docs/release-X.Y.Z.md` any more. The CHANGELOG is the one place a release is written. The
old `docs/release-*.md` files stay as history.

## Release checklist

1. `CHANGELOG.md`: new entry at the top, within the word limit.
2. `README.md`: bump the version line; update **Known issues** if they changed. Still under 600 words.
   The fork's latest release has an installer and the API this release needs (see above).
3. Grep for the old version number (`M.VERSION` in `mod/`, versioned doc names like `pacenotes-X.Y.Z.md`) and
   update what should move.
4. `python tools/release.py X.Y.Z-alpha --check`, then without `--check`: it commits, tags `vX.Y.Z-alpha`, builds the
   zip, pushes and makes the GitHub pre-release with the title, body and asset above. The maintainer runs it.

## Other docs

`docs/guide.md`, `docs/pacenotes-*.md`, `docs/rally-file.md` and the plan and notes files are reference, not held
to these word limits. They still follow the rules for all three: plain words, keys bold, paths in code.

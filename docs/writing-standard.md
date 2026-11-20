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

**Alpha · BeamNG.drive <ver> · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) <ver>+**
[Download](…/releases) · [Wiki](…/wiki) · [Changelog](CHANGELOG.md) · [Player guide](docs/guide.md) · [Report a bug](…/issues)

<hero screenshot from docs/media/>

## What it does        5-8 one-line bullets
## Install             3-5 numbered steps; official BeamNG.Earth first; its Add-ons page, Add from
                      GitHub: DeRamp/BeamNG.Earth.Rally, then DeRamp/earth-rally-leaderboards (Start)
## Updating            1-3 bullets: updates come through the Add-ons page, the old zip deleted, what carries over
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

Works with BeamNG.drive 0.40.5 · [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10+.

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
* **Asset:** `earth_rally-X.Y.Z-alpha.zip` from `tools/release.py`, with the ARA 2026 season inside it
  (`earthRally/import/ARA Nationals 2026/`). Nothing else attached: the Add-ons page installs the first `.zip`.
* **Pre-release** box NOT ticked (since 1.8.0): BeamNG.Earth's Add-ons page installs only the newest full release.
  The version keeps its `-alpha`.
* **Body:** the CHANGELOG entry, pasted, then this block:

```markdown
---
**Install:**
1. Install [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases) 1.10 or newer with its installer.
2. In BeamNG.Earth, open **Add-ons** > **Add from GitHub**, paste `DeRamp/BeamNG.Earth.Rally` and press **Install**.
3. Paste `DeRamp/earth-rally-leaderboards` the same way, press **Install**, then **Start** (tick
   **Start with BeamNG.Earth**).
4. Load BeamNG.Earth's freeroam and press **Ctrl + Alt + K**. The ARA 2026 season is included.

**Moving from the zip install:** delete `earth_rally-*.zip` from `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\`.

[README](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/README.md) · [Player guide](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/docs/guide.md) · [Full changelog](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/CHANGELOG.md)
```

### BeamNG.Earth: official

Since 1.9.0 every release points players at the **[official BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth/releases)** (1.10+). The auto recce uses
the modding API's `api.roadGraph` where a BeamNG.Earth has it (the DeRamp fork, PR #1249) and walks the car along
the stage where it does not. The DeRamp fork is no longer linked from player material.

There is no separate `docs/release-X.Y.Z.md` any more. The CHANGELOG is the one place a release is written. The
old `docs/release-*.md` files stay as history.

## Release checklist

0. The version number is confirmed with the owner: patch for fixes and small improvements, minor for a major new
   feature (`CLAUDE.md`, Branches and releases).
1. `CHANGELOG.md`: new entry at the top, within the word limit.
2. `README.md`: no version number in it (it says alpha); update **Known issues** if they changed. Still under 600 words.
3. Grep for the old version number (`M.VERSION` in `mod/`, versioned doc names like `pacenotes-X.Y.Z.md`) and
   update what should move.
4. Land these on `main` (see `CLAUDE.md`).
5. `/release X.Y.Z-alpha` runs `python tools/release.py X.Y.Z-alpha <commit>`: it tags the commit,
   builds the zip from the tag (plus the ARA 2026 season) and makes the GitHub release (not a pre-release) with the title, body and asset above.

## Other docs

`docs/guide.md`, `docs/pacenotes-*.md`, `docs/rally-file.md` and the plan and notes files are reference, not held
to these word limits. They still follow the rules for all three: plain words, keys bold, paths in code.

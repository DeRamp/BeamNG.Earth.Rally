# Handoff: where Earth Rally stands (2026-11-14, after the 1.2.5 release)

Read this first in a new session.

## The project

Earth Rally (this repo, github.com/DeRamp/BeamNG.Earth.Rally, MIT, by DeRamp): a BeamNG.drive 0.40.5 mod that
runs real rally stages on BeamNG.Earth (github.com/TecnaGamer/BeamNG.Earth, a streamed real-world map mod), timed,
with the game's own co-driver calling pacenotes made from the road. Maps (KML/KMZ/GPX, also `.kml.xml`) dropped in
`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\earthRally\import\` become rallies.

Upstream: our PR "Modding API 1.7: onBeamNGEarthRebased" (TecnaGamer/BeamNG.Earth#1183) is merged into BeamNG.Earth's
`dev` (b28afde9); in dev builds from 1.9.1-beta.dev.398, not in stable 1.9.1-beta.

## Branches: work on `main`

**`main` is the trunk and the only branch anything new goes on.** A release is a tag on `main`
(`vX.Y.Z-alpha`) plus a GitHub pre-release carrying the zip from `python tools/package.py <version>`.

`v1.2.0`, `v1.1.0` and `auto-test` are kept as history and nothing is committed to them again. Everything they hold
is in `main` and in the tags, so they are a record, not a place to work. Read the warning in them: `v1.2.0` was the
working branch from 1.2.0 right through 1.2.5, so its name meant nothing by the end, `main` sat at the 1.2.1 release
for days, and the repository's front page advertised a version two releases old with a known issue that had been
fixed twice. If a version needs a branch of its own, give it one and merge it back the week it is done.

Releases: v1.0.0-alpha, v1.1.0-alpha, v1.2.0-alpha, v1.2.1-alpha, v1.2.2-alpha, **v1.2.5-alpha** (all GitHub
pre-releases). 1.2.3 and 1.2.4 were not released separately -- they are in 1.2.5.

## Where 1.2 ended (2026-11-13, driven in game)

Everything reported while testing is fixed, and `docs/notes-1.2.4.md` has no open items. The last evening fixed:
the on-stage display reaching the game at all (1.2.2's install-script fault), the stage clock and progress meter at
the top of the screen, the grey washes removed, the rally block in the top left corner, and then 1.2.5's one panel:
BeamNG.Earth's place-name strip and connection banner off screen for the stage with the rally HUD drawing where you
are and what it has to say, as rows of its own card before a stage and as a thin sliver beside the stage clock on it.
Also: a run begun parked at the control no longer checks in instantly (which also fixed the ATC's boards standing
off the road -- the road was 0.8 m away, BeamNG.Earth simply had not streamed it), the skip prompt is no longer
clipped, and the HUD hides while a menu is up.

## What 1.3.0 picks up

`docs/roadmap.md` and `docs/version-plans.md` hold the plan; `docs/plan-1.3.0.md` has the detail. The theme is
**stages for everyone**: road matching with no Python (a BeamNG.Earth companion add-on), stage pre-loading, an ATC
added to stages without one, folder-based import, version checks at startup.

Two things carried out of 1.2 that belong early in 1.3:

- **The self-test cannot check the co-driver.** `tools/selftest.py` walks the car along the stage line, which is
  deterministic and takes about four minutes, and it passes 22 of 23 checks -- but the game decides whether to call
  a pacenote from the car's rigid-body velocity, and a car set down frame by frame has none. The game's own AI does
  make them play, but it cannot drive a BeamNG.Earth stage: `ai.driveUsingPath` keeps its route in a graph installed
  with `mapmgr.setCustomMap()`, and BeamNG.Earth tells every vehicle to `mapmgr.requestMap()` whenever it streams new
  roads, which throws that route away. The lead worth following is `drivelineRoute:setVehicleTracker()`, the engine's
  own seam: a tracker reporting a synthetic speed and position would drive the whole pacenote pipeline.
- **A pull request to BeamNG.Earth for `api.hudHide`.** Earth Rally takes its strips off screen by dropping the apps
  from the stage layout and telling BeamNG.Earth they are mounted anyway (`core.hudApp`, its own published call), so
  it does not draw them with ImGui instead. That works and touches no data path and no player setting, but it is a
  polite fiction that upstream could tidy away without warning. The clean shape is ~30 lines: `hudapps.setHidden`
  plus `api.hudHide` / `hudShow` / `hudHidden` behind `has('hud')` -- the same size as the rebase PR.

## How the user works

- **An issue means a plan, not a change.** When they report something, work out how it would be fixed and put that
  to them; build it when they say so. This holds for one-line fixes too.
- **UI together:** show a mock-up first and wait for agreement before writing UI code. Mock-ups are self-contained
  HTML in `docs/mockups-<version>/`, drawn at the game's own 1920x1080 positions with a now/proposed toggle.
- **While they test, log what they report** into `docs/notes-<next version>.md`, with enough diagnosis that it is
  not rediscovered later.
- Small things go in the next patch version; large systems go to a later minor version (propose which).
- **Don't install, push or release without being told.** Releases are GitHub pre-releases.
- **Don't move windows on their PC.**
- They often dictate with speech-to-text, so game sounds sometimes land as stray words in a message.

## This machine

BeamNG.drive 0.40.5 (Steam). BeamNG.Earth checked out at `../beamng.earth` on `dev`, with its `.venv` built -- which
is where `tools/selftest.py` and `tools/playtest.py` find it, and what `tools/match_roads.py` needs. Python 3.13 with
`lupa` for the offline tests (`python tests/run_tests.py`, 11 files). GitHub CLI installed at
`C:\Program Files\GitHub CLI\gh.exe`, logged in as DeRamp, and `gh auth setup-git` done so `git push` works.

The rally data (imported events, recces, matched lines, times) lives in the BeamNG user folder and the `Rally Docs`
folder, and is deliberately not in this repository: the organisers' maps are theirs.

`python tools/playtest.py` is the loop -- install, start the game through Steam, go straight to a stage.

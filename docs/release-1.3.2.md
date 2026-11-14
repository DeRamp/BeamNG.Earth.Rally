# 1.3.2: the first stage goes right

**In progress.** Three of the six items in `docs/roadmap.md`'s 1.3.2 are built and tested offline; none has been
driven yet. The order of work and the reasoning are in `docs/version-plans.md`.

Everything here is about the first stage somebody drives: the start that counted itself down before they were
ready, three rallies in the menu wearing the same name, and a mod that says nothing when the two projects under it
move on.

---

## 1. A stage with no arrival control no longer counts down the moment it spawns you

Reported 2026-11-13: *"when you start a stage that dosent have an atc, the stage imediatly starts a count down.
instead it should spawn you behind the start line so you can wait for the game to load before you go"*.

The car **was** already put behind the line — 4 m behind it, inside a **12 m** start zone. So it was standing
stopped inside the zone on the first frame the zone was asked about, the start was set 12 seconds later whatever
the world was doing, and the drive up to the line never happened. It is the same defect `DRIVEN_THERE_MIN_M` was
added for on the ATC path the day before, in the sibling path nobody checked for it.

It now gets the same two moves that path got:

* **The car is set down 25 m before the line**, outside the zone, and a message says *"Drive up to the start line
  when you are ready."* Three ways back, in order: along the stage's own line where there is line before the start
  to back along; else back along the road map's road, which follows the bends; else straight back along the
  stage's direction. The developer panel's `startSetDown` says which one ran.
* **"Stopped on the line" is not a start until the car has moved since it was put there.** The spot is held in
  lat / lon rather than game coordinates, so the world moving its origin while you wait does not stale it.

**Two things deliberately unchanged.** The **quick-start setting** still does exactly what it says — car on the
line, clock a few seconds after it stops — because that is a player asking for this behaviour, and the two cases
were sharing one code path, which is most of why this was wrong. And a car **you** drove to the start (Route to
start, say) is left where you left it, in the same band the ATC path uses.

**Open, for the user:** on a stage with no arrival control, after you drive up and stop on the line, should it
still be a flat 12 s (`NO_ATC_START_S`, which exists so the co-driver's 10-second call fits), or a real start
minute the way checking in at an ATC gives you? A minute is what a rally does; 12 s is friendlier on a stage with
no controls at all. The guard is the same either way, so this is not blocking — it is left at 12 s.

## 2. Three rallies called "Main Route Book"

Of the twelve rallies imported on this machine, **three came in as "Main Route Book", "Main Route Book" and
"(Main Route Book)"** — SOFR Thursday, Friday and Saturday — because that is what the organisers called the
document inside all three files. Three identical rows in the menu. Two more carried a file extension in the middle
of their name ("2026 Overmountain - Publish v2.kmz"), for the same reason: it was in the organiser's own document
name.

A rally's name now comes from the document's `<name>` only where that name says which rally it is. Where it does
not — a list of names like *main route book*, *untitled map*, *maps*, *competitors* — the **file's** name is used
instead, which is the one thing that does tell those three apart. Names are tidied either way: no file extension,
underscores as spaces, no trailing "KML".

The rule is deliberately **not** "prefer the file name when another rally already has this name". That would
depend on the order the import folder is read in, so the same three files could come out named differently on
another machine or after a re-import, and a name a player reads should not move about.

**The three on this machine are renamed without you doing anything.** A map already imported is normally skipped
while its bytes have not changed, so a change to what a rally is *called* would otherwise only reach rallies you
happen to re-import. `importer.NAME_RULES` is a number in the import index: when it does not match, the next scan
reads every map again, **keeping each rally's id**, so its recces, matched lines and times still belong to it.

Worth saying plainly: this roadmap item was written as *"maps that group stages in folders import properly"*. The
folders were never the problem — every Placemark in a KML is read wherever it sits, and always was. The name was.

## 3. Version checks at startup

The mod sits on two projects that move on their own release schedules, and when one changes under it the symptom a
player meets is a stage behaving oddly, not a message. `versions.lua` now says, in the log on every start and on
the Rallies page when there is anything to say:

* **BeamNG.drive's version**, against the 0.40.5 this was built and driven on. A *warning*, never a refusal — a
  mod built on 0.40.5 usually survives 0.40.6 — and it says whether the rally engine still looks the same, so a
  version difference that broke nothing is not chased.
* **The game's rally engine**, which is the actual gate: the co-driver and the stage line come from it, and a
  stage that loads against a changed one is worse than a stage that does not load. This check existed; it now runs
  at startup rather than only when a stage is started.
* **BeamNG.Earth's modding API.** Older than 1.6 is refused with both figures. A different *major* is now refused
  as a different API rather than as an old one — before this, a 2.x was told it was "too old", which would have
  sent a player looking for an update they already had. Newer than the 1.9 this was built on is said and not
  refused, since the project has only ever added calls.
* **The seven things BeamNG.Earth has no API for** that Earth Rally reaches into — `core.rebaseTo`,
  `core.hudApp`, `core.setRebaseDistance`, `core._state`, `camshift.RADIUS_MIN`, `banner.current`,
  `rebase.distance` — each by name, with what stops working if it goes. None of them is in the versioned surface,
  so a rename need not bump any number and the name going missing is the only signal there is.

What no version check can catch is one of those keeping its name and changing its behaviour; `earthAdapter`'s
`holdStrips` comment says what that one would look like.

---

## Tests

| | |
|---|---|
| `test_run` | 395 checks, 0 failed — including the no-ATC start, the quick-start setting, a car driven to the start, the way back along the line, and `onStartLine`'s own table of cases |
| `test_import` | 69 checks, 0 failed — the naming rules on all twelve of this machine's real map files, and the one-off re-import |
| `test_versions` | 49 checks, 0 failed — every finding the startup check can make, driven through a pure function rather than through this one machine |

**Mutation-tested**, because the first run of these tests passed every new assertion first time, which is a reason
to be suspicious rather than pleased: fourteen deliberate breakages of the new code, all fourteen caught. Two
things came out of that run and not out of the tests themselves — a straight-line distance term in the start
trigger that read plausibly and was redundant (it survived its own deletion, so it went), and the fact that the
movement guard is not belt-and-braces over the placement but the only thing standing between the player and this
bug at a start inside a hairpin.

## What to look at in game

1. **A stage with no ATC, full time controls.** Drive stage. You should be set down ~25 m short of the line, with
   nothing counting down, for as long as you like. Drive up, stop, and the clock starts.
2. **The same stage with Quick start on the line.** Unchanged: on the line, away a few seconds after you stop.
3. **Route to start, then Drive stage.** You should not be moved.
4. **The menu's rally list.** The three SOFR rallies should read "2026 SOFR Thursday / Friday / Saturday", and
   Overmountain and Colorado should have lost their ".kmz". Nothing else should have changed name, and no rally
   should have lost its recces or times.
5. **`beamng.log` at startup.** One `versions:` line with all three versions. On the fork, nothing after it.

# 1.3.2: the first stage goes right

Everything here is about the first stage somebody drives: a start that counted itself down before they were ready,
three rallies in the menu wearing the same name, and a mod that said nothing when the two projects under it moved
on. The roadmap's 1.3.2 is in `docs/roadmap.md`; the order of work is in `docs/version-plans.md`.

---

## A stage with no arrival control no longer counts down the moment it spawns you

Reported 2026-11-13: *"when you start a stage that dosent have an atc, the stage imediatly starts a count down.
instead it should spawn you behind the start line so you can wait for the game to load before you go"*.

**This is the common case, not an edge case.** Of the 116 stages in the twelve rallies on my own machine, **90 have
no arrival control in their map at all** — six of the twelve rallies have none on any stage.

The car *was* already being put behind the line — 4 m behind it, inside a **12 m** start zone. So it was standing
stopped inside the zone on the first frame the zone was asked about, the start was set 12 seconds later whatever
the world was doing, and the drive up to the line never happened. It is the same defect `DRIVEN_THERE_MIN_M` was
added for on the arrival-control path the day before, in the sibling path that was never checked for it.

It now gets the same two moves that path got:

* **The car is set down 25 m before the line**, outside the zone, with *"Drive up to the start line when you are
  ready."* Three ways back, in order: along the stage's own line where there is line before the start to back
  along; else along the road map's road, which follows the bends; else straight back along the stage's direction.
* **"Stopped on the line" is not a start until the car has moved since it was put there.** The spot is held in
  latitude and longitude rather than game coordinates, so the world moving its origin while you wait does not
  stale it.

A car **you** drove to the start — Route to start, say — is left where you left it, in the same band the arrival
control path uses.

## "Quick start on the line" is gone from Settings

It put the car on the start line and started the clock a few seconds later, skipping a stage's arrival control.
That is the behaviour the fix above exists to stop doing, kept as an option. With the ordinary path now letting
you set off when you are ready, it was two code paths for one job — and that sharing is most of why the bug above
was written in the first place. A settings file that still carries it is not a mistake the player made, so it is
dropped quietly rather than warned about.

## Three rallies called "Main Route Book"

Of the twelve rallies imported here, **three came in as "Main Route Book", "Main Route Book" and "(Main Route
Book)"** — SOFR Thursday, Friday and Saturday — because that is what the organisers called the document inside all
three files. Three identical rows in the menu. Two more carried a file extension in the middle of their name
("2026 Overmountain - Publish v2.kmz"), for the same reason.

A rally's name now comes from the document's `<name>` only where that name says which rally it is. Where it does
not — *main route book*, *untitled map*, *maps*, *competitors* and the like — the **file's** name is used instead,
which is the one thing that tells those three apart. Names are tidied either way: no file extension, underscores
as spaces, no trailing "KML".

The rule is deliberately **not** "prefer the file name when another rally already has this name". That would depend
on the order the import folder is read in, so the same three files could come out named differently on another
machine, and a name a player reads should not move about.

**The rallies already on your machine are renamed without you doing anything**, keeping each rally's id so its
recces, matched lines and times still belong to it.

This was on the roadmap as *"maps that group stages in folders import properly"*. The folders were never the
problem — every Placemark in a KML is read wherever it sits, and always was. The name was.

## Version checks at startup

The mod sits on two projects that move on their own release schedules, and when one changes under it the symptom a
player meets is a stage behaving oddly, not a message. It now says, in the log on every start and on the Rallies
page when there is anything to say:

* **BeamNG.drive's version**, against the 0.40.5 this was built and driven on. A warning, never a refusal, and it
  says whether the rally engine still looks the same so a version difference that broke nothing is not chased.
* **The game's rally engine**, which is the real gate: the co-driver and the stage line come from it.
* **BeamNG.Earth's modding API.** Older than 1.6 is refused with both figures. A different *major* is now refused
  as a different API rather than as an old one — before this a 2.x was told it was "too old", which would send a
  player looking for an update they already had. Newer than the 1.9 this was built on is said, not refused.
* **The seven things BeamNG.Earth has no API for** that Earth Rally reaches into — `core.rebaseTo`, `core.hudApp`,
  `core.setRebaseDistance`, `core._state`, `camshift.RADIUS_MIN`, `banner.current`, `rebase.distance` — each by
  name, with what stops working if it goes. None is in the versioned surface, so a rename need not bump any number
  and the name going missing is the only signal there is.

In a game, on the machine this was built on, it says one line and nothing else:

```
versions: Earth Rally 1.3.2-alpha on BeamNG.drive 0.40.5.0.302427 (built for 0.40.5), BeamNG.Earth API 1.9
```

## Known

* **The menu can come up with no styling** once BeamNG.Earth's map page has been opened in the same session. It is
  not Earth Rally's doing and not BeamNG.Earth's: both mods register a full-screen route the way BeamNG's own
  `ui/ui-vue/mods/README.md` documents, and in both mods it is the **route** that breaks while the pause-menu tab
  — which the game loads from a path — survives. It did not reproduce after a `reloadUI()`, so it is intermittent.
  `reloadUI()` in the console (`~`) puts it right. The investigation is in `docs/notes-1.3.2.md`.
* **BeamNG.Earth's map page logs a `ResizeObserver` loop** every time it is opened (246 errors in one session
  here), settling after a few seconds. Upstream, and separate from the above.
* `seconds` in a matched line's file still reads 0 for a recce that took under a second. Cosmetic.
* The auto recce's estimate can still over-ask; **Not now** costs nothing.

## Still open, for the next version

On a stage with no arrival control, after you drive up and stop on the line, the start is a flat 12 s
(`NO_ATC_START_S`, which exists so the co-driver's 10-second call fits). A real start minute, the way checking in
at a control gives you, is what a rally does; 12 s is friendlier on a stage with no controls at all. The guard
works the same either way, so it is left at 12 s until decided.

Three 1.3.2 items are not in this release and move on: an arrival control added to stages that have none, dropping
the late-start penalty, and stage pre-loading before the start.

## Tests

| | |
|---|---|
| `test_run` | 394 checks — the no-ATC start, a car driven to the start, the way back along the line, `onStartLine`'s own table of cases, and the developer panel drawing through |
| `test_import` | 69 checks — the naming rules on all twelve of this machine's real map files, and the one-off re-import |
| `test_versions` | 59 checks — every finding the startup check can make, and that it does not drag the game's rally engine in at the main menu |
| `test_hud` | 355 checks |
| and the rest | `test_geo`, `test_props`, `test_selftest`, `test_compile`, `test_mapkey`, `test_install`, `test_selftest_tool`, `test_import_parity` |

**Mutation-tested**: nineteen deliberate breakages of the new code, all nineteen caught. Three things came out of
those runs rather than out of the tests — a distance term in the start trigger that read plausibly and was
redundant (it survived its own deletion, so it went); that the movement guard is not belt-and-braces over the
placement but the whole of the fix at a start inside a hairpin; and a fixture mutation that leaked into a later
test.

**Not run for this release:** the two tests that drive the mod to BeamNG.Earth's real server and back. They need
the machine's sockets and a server of their own, and the game was running. Nothing in this release touches the
wire, the server, or either API call.

# 1.7.2 notes: download progress and Stop all

Branch `fix/download-progress`, from `main` at 1.7.1. Build: `1.7.1-alpha+progress`, released as 1.7.2-alpha.
Mock-up, approved by the owner 2026-11-16: [`mockups-1.7.2/download.html`](mockups-1.7.2/download.html).

## What the owner asked

- "Better progress bars for auto recce downloads." Perkins on Ojibwe sat at 2 of 59 for 45 s, then finished at
  49 s. It looked hung.
- "When you're downloading an entire set of stages ... if you click stop, it should stop all downloads ...
  Otherwise, you have to keep clicking it."

## Why

- BeamNG.Earth reports a count of items, not bytes (`areaStatus`: state, done, total). The items differ a lot in
  size, so the count sits still while a big one comes down. No bar can fill honestly through that.
- A full rally gets its stages ready one auto recce after another (`stepRallyPrep`). Stop cleared only the one
  under way, and the prep started the next a frame later.

## What changed

- **Stage page:** the auto recce card shows the four steps of one press (Check, Download, Go to the start, Match
  the line), a full-width bar, the time so far and the size asked about. Stripes run along the bar while it works,
  and the fill moves only on the real count. After 15 s with no new item, a yellow line says a big piece is
  downloading.
- **Stage row and banner:** the pill is striped while it works and shows the time (`2/59 · 0:30`).
- **Time card, getting the stages ready:** the bar is striped too, the download's time shows, and a Stop button
  stops them all.
- **Stop during a full rally's prep** stops every stage left in one press, with the ending a Stop on each reached:
  the prep ends, a stage with no line is held out, and the rally goes on. The buttons say `Stop all N`.
- **Stop's message says what happened:** how many stages were held out, or "No stage has its line yet, so the
  rally ended" when none is left to drive (a first run where no stage has a line). It also says a map download
  already started carries on in BeamNG.Earth's Areas.
- **Held out, with the reason:** the time card and start screen said "road missing from the map" for every
  held-out stage. They now give each stage's own reason, such as "no line on the roads".
- Not done: leaving the rally on Stop (the first cut). A rally just started is not saved until its first service,
  so leaving would throw it away, and Save and quit has its own button and confirm.
- Not possible: BeamNG.Earth's API cannot pause or remove an area, so a download already handed to it carries
  on in its Areas list.

## Files

- `main.lua`: `quietS`, `bytes`, `downloaded` and `prepLeft` in the page's state; Stop ends the prep.
- `rallyRun.lua`: `prepDone` returns how many it held out and whether the rally ended.
- `store.js`: `mmss`, the download clock.
- `EarthRally.vue`: the stage page's card, the striped pill, the Stop labels, the time in the banner.
- `EarthRallyFull.vue`: the prep tracker's stripes, time and Stop.
- `tests/test_run.lua`: Stop through the real prep, both endings: two stages held out and the rally goes on; no
  line anywhere and the rally ends. The new download fields are there.

## For the owner to decide

- Should Stop cut the stages left out of this rally (as now, and as a Stop on each did), or stop and let you try
  them again later? The second needs the prep to be resumable.
- Stop has no confirm. On a first run where no stage has a line, it ends the rally.

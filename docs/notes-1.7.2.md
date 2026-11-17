# 1.7.2 notes: download progress and Stop all

Branch `fix/download-progress`, from `main` at 1.7.1. Build: `1.7.1-alpha+progress`, lands as the next patch.
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
- **Time card, getting the stages ready:** the bar is striped too, the download's time shows, and a **Stop
  getting ready** button stops them all.
- **Stop during a full rally's prep** stops every stage left and leaves the rally as Save and quit does. Stages
  already matched stay ready, so starting or continuing gets only the rest ready. The buttons say `Stop all N`.
- Not done: holding the unfinished stages out (`prepDone`) would take them out of the rally for good.
- Not possible: BeamNG.Earth's API cannot pause or remove an area, so a download already handed to it carries
  on in its Areas list.

## Files

- `main.lua`: `quietS`, `bytes`, `downloaded` and `prepLeft` in the page's state; Stop ends the prep.
- `EarthRally.vue`: the stage page's card, the striped pill, the Stop labels, the time in the banner.
- `EarthRallyFull.vue`: the prep tracker's stripes, time and Stop.
- `tests/test_run.lua`: Stop during a prep stops all three and leaves the rally; the new fields are there.

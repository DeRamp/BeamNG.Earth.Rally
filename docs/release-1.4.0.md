# 1.4.0: rally files

Earth Rally can now hold a whole season. Drop a **rally pack** into the import folder, a folder or a `.zip` with
the maps, the itinerary, the real results and some pictures, and the menu shows **season > rally > stage**, a
leaderboard of the real crews' times on every stage, a rally total, and season standings. The roadmap's 1.4.0 is in
`docs/roadmap.md`, and the format is in `docs/rally-file.md`.

Every version after this one moved up by one: on the stage is now 1.5.0, the co-driver 1.6.0, making and sharing
stages 1.7.0, and the full rally 1.8.0.

---

## Seasons, rallies and stages

* **Rallies** shows your seasons and your one-off rallies as cards, with their covers.
* **A season** lists its rounds, with dates, how many stages you have driven, and your place in each round.
  **Standings** ranks you against the real crews over the season.
* **A rally** shows its banner and its stages. A stage run more than once is one row (*SS2 · SS4*), a pass
  cancelled on the day is struck out, and a stage in the map but not in the itinerary says *Not run*. **Results**
  and **Rules** sit beside **Stages**.
* **A stage** has its leaderboard, with **Your runs** below it.

The menu opens where you left it, whether you use **Ctrl + Alt + K** or **Rally menu** on the pause menu's Earth
Rally tab. That tab is now just that one button, and Settings lives in the menu itself.

A map dropped in on its own works as before: it is a rally of its own, outside any season.

## Leaderboards from real results

When a pack has results, each stage's leaderboard is the real field. It shows the **top 10**, and when you are
lower than that, **the crew just ahead of you, you, and the crew just behind**, with your place out of the
whole field ("42nd of 95"). A stage run twice has a toggle between its passes. By default it opens on the pass you
place best on.

**A time is only placed when the line under it is the real stage.** If your line runs more than 5 % longer or
shorter than the official distance, start to flying finish, the leaderboard says so, and the time stays in **Your
runs**. The check uses the line you are actually timed on (your recce or the auto recce's), and falls back to the
map's line when there is neither. Each time now records which line it was driven on, so a time from before a
stage's line was remade is not placed against the new one.

## A rally total and the standings

A rally's **Results** adds your best on each stage up into a total and ranks it against the crews who finished.
Where some stages' lines don't match the official distances, the total is ranked over the ones that do, and says
so ("ranked over 14 of 16 stages"). If those stages cover less than three quarters of the rally's distance, the
total is shown but not ranked.

**Season standings** give points by each rally's finishing order: 25, 20, 16, 13, 11, 10, 9 … 1 by default, or the
season's own scale if its pack has one. Power-stage points are left out for now. The real crews' points always
come from their real results, and your result never moves anyone else's place.

## Rally packs

A pack is a folder, or a `.zip` of one, with a `season.json`, `rally.json` or `stage.json` at its top. Everything
in it is optional except the maps. A season lists its rounds, and each round brings its map, and can also bring:

* an itinerary (which stage runs as which SS, and on which day)
* results
* rules (false starts, early and late at a control)
* a cover, a logo and a photo

Packs are re-read only when they change. A pack that is renamed keeps its ids, so your recces, lines and times
stay with it. The full format is in `docs/rally-file.md`.

**Packs are yours.** Organisers' maps, photos and results belong to them, and results name real people, so no pack
of a real event ships with the mod. Ask the event before you pass one on.

## Also

* The Settings page's **HUD preview** button is gone. It was a developer tool, and it is still in the developer
  panel.
* Known: a pack imported from a `.zip` has not yet been seen working in game. A folder has.

# 1.7.1 notes: the auto recce download

Branch `fix/auto-recce-download`, from `main` at 1.7.0. Build: `1.7.0-alpha+download`.

## What was wrong

- On BeamNG.Earth fork.1 (upstream 1.10) the auto recce's download looked hung.
- 1.10 dropped the ten-area cap. On 1.9.1 every download was refused (19 areas saved), so the auto recce
  matched at once with what was on disk. Now it really downloads: Steamboat, 55 MB, took 66 s.
- The download wrote nothing to the log, and the game was closed 8 s before it finished.
- Each Download added a new saved area, even for a stage that had one (Stage Road ×3, Orchard - Shoreline ×2).

## What changed

- Download on a stage that already has an area uses that area. The press still prices and asks every time.
- The stage's area id is kept in `settings/earthRally_areas.json`.
- The log says when the area is taken, its progress every 10 s, and when it finishes.
- A paused or deleted area ends the wait with a line saying so, instead of waiting 30 minutes.
- The menu says the download can take a few minutes.

## To test

- Auto recce a stage with missing data, say Download, and wait for it: it goes on to the stage and matches.
- Press Auto recce again on the same stage and say Download: BeamNG.Earth's area list gets no new entry.
- Pause the area in BeamNG.Earth's list mid-download: the auto recce stops and says it is paused.
- Start a full rally with stages that have no line: the time card shows "Downloading the map · N of M".

## Not done

- The old duplicate areas stay: delete the extra Stage Road and Orchard - Shoreline areas by hand.
- The estimate over-asks (a corridor two map cells wider than the match reads). Narrowing it is for later.
- The fork's server crashed on shutdown ("PyEval_SaveThread ... GIL is released"). That is a fork bug.

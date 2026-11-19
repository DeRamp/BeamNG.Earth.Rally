# Notes: 1.9.0-alpha+walkcache test

## 1. "Recce recommended" on stages that are road the whole way (2026-11-19)

**Seen:** Bolster Hollow matched 5.8 km with 3510 m "no road" in 3 stretches. Steamboat: 8000 m in 8 stretches.

**Not the walk or the cache.** The roads are in what the walk read. Bolster Road, Bolster Hollow Road and Coalmont
Hollow Road (OSM, residential) are all within 15 m of cached road nodes.

**Cause:** the organisers' line is too coarse. Bolster Hollow's line has 12 points for 5.9 km, with straight runs of
1.0 and 1.4 km. Steamboat's has 90 points, with 29 runs over 300 m and the longest about 2 km. Where the real road
bends away from a straight run, it is 100-260 m off the line. The matcher (`autoRecce.lua`) only takes a road within
`SNAP_M` = 60 m of each waypoint, so those stretches are marked no road and the stage shows **Recce recommended**. The
fork matches the same way, so it would have done the same.

**Fix options (plan, not built):**
- When a waypoint misses, retry it with a wider snap (say 250 m, inside `CORRIDOR_M` 300). Only take the road if it
  joins up with the matched road before and after, so a wrong parallel road isn't picked.
- Or weight the snap by how long the straight run around the waypoint is: a long run means a rough line, so allow
  more.
- Touches `autoRecce.lua` (waypoint snap) and `tests/test_autorecce*.lua`.

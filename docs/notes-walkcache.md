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

**Built (owner: "implement this fix"):**
- `autoRecce.lua`: where the organisers' line has a straight of `SPARSE_M` (300 m) or more, a run of waypoints that
  miss the road is bridged by routing from the matched road before it to the matched road after it, within the
  detour limit. The detour limit now grows with how far each snapped point is off the line. A well-drawn line keeps
  its gaps. (A 250 m wide snap was tried first and dropped: it could land on a spur and draw an out-and-back.)
- `walkCache.lua`: a fresh read deleted old links that crossed its edge, cutting Bolster Hollow Road in two in the
  cache. Now it keeps links it cannot see, and drops a node's links in every tile.
- On the cached roads (cut links restored): Bolster Hollow no road 3510 m -> 0, Steamboat 8000 m -> 1600 m.
- Still there: Steamboat 6400-8000 m. Bolster Hollow's line doubles back near 2.3 km (as before; it is the
  organisers' line).
- Not done: `tools/auto_recce.py` has no bridge. walkCache: a node that moves tile keeps a stale copy; `read` misses
  an edge filed under a node outside its reach (both low, from the debugger).

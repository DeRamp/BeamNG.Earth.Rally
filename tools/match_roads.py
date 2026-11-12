#!/usr/bin/env python3
"""Match each stage's map line to BeamNG.Earth's own roads, with heights, so the stage runs without a recce.

The game drives on BeamNG.Earth's roads: Overture's road data per map cell, every bend rounded to an arc by
BeamNG.Earth (server/roadsmooth.py). This reads those cells with BeamNG.Earth's own code (its download cache, fetching
the cells it lacks), routes along them from point to point of the organisers' line (every WAYPOINT_M), preferring
roads close to that line, and takes the heights from BeamNG.Earth's elevation data. Where no road on the map is near
the line, the organisers' line is kept for that stretch and the stage is flagged: those stretches want a recce.

Writes <BeamNG user folder>/current/earthRally/matched/<event>__<stage>.json; the mod runs a stage on it when the
stage has no recce (a recce, when there is one, is still used first).

Needs BeamNG.Earth's source (a clone of github.com/TecnaGamer/BeamNG.Earth) and its Python environment (numpy):

    <beamng.earth>/.venv/Scripts/python.exe tools/match_roads.py --earth <beamng.earth> --event olympus26
    ... --event otr24 --stage maryhill-up            (one stage)

A developer tool for now: the plan is to move this into BeamNG.Earth's server as an API call, so players need nothing.
"""
import argparse
import heapq
import json
import math
import os
import sys
import time

WAYPOINT_M = 400.0      # the organisers' line is followed through a point every this many metres
SNAP_M = 60.0           # a waypoint this close to a road is on it (else that stretch has no road on the map)
NEAR_M = 15.0           # a road this far from the organisers' line costs double per metre (quadratic beyond)
CORRIDOR_M = 300.0      # roads further than this from the line are not used
DETOUR_MAX = 1.4        # a route between two waypoints longer than this times their distance along the line + 100 m
                        # is a detour: that stretch is kept as the organisers' line
MERGE_M = 0.75          # vertices this close are one node
PIECE_M = 20.0          # roads cut into pieces no longer than this
BRIDGE_M = 3.0          # a dead end this close to another road is joined to it ...
BRIDGE_ON_LINE_M = 25.0 # ... or this close when both lie on the organisers' line (within ON_LINE_M): a break in the
ON_LINE_M = 12.0        # map's road where the stage plainly goes on
OUT_STEP_M = 4.0        # the matched line's point spacing (as a recce's)
HEIGHT_OFFSET_M = 0.2   # a recce's heights (the car's position) sit this far above the elevation data
NOT_ROADS = {'footway', 'path', 'cycleway', 'steps', 'pedestrian', 'bridleway', 'corridor', 'sidewalk', 'crosswalk'}


def user_dir():
    base = os.environ.get('LOCALAPPDATA')
    if base:
        return os.path.join(base, 'BeamNG', 'BeamNG.drive', 'current')
    return os.path.expanduser('~/.local/share/BeamNG/BeamNG.drive/current')


class Frame:
    def __init__(self, lat, lon):
        self.lat0, self.lon0 = lat, lon
        self.kx = math.radians(1) * 6371008.8 * math.cos(math.radians(lat))
        self.ky = math.radians(1) * 6371008.8

    def xy(self, lat, lon):
        return (lon - self.lon0) * self.kx, (lat - self.lat0) * self.ky

    def latlon(self, x, y):
        return self.lat0 + y / self.ky, self.lon0 + x / self.kx


def resample(xy, step):
    """The polyline every `step` m along it (first and last points kept), and the distance along it of each."""
    out, along = [xy[0]], [0.0]
    acc, carry = 0.0, 0.0
    for a, b in zip(xy, xy[1:]):
        seg = math.dist(a, b)
        pos = step - carry
        while pos <= seg:
            t = pos / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            along.append(acc + pos)
            pos += step
        carry = seg - (pos - step)
        acc += seg
    if math.dist(out[-1], xy[-1]) > step * 0.25:
        out.append(xy[-1])
        along.append(acc)
    return out, along


def seg_dist(np, P, A, B):
    """Distance of each point of P (n, 2) to the polyline segments A -> B (m, 2) each: (n,) minimum."""
    best = np.full(len(P), np.inf)
    D = B - A
    L2 = np.maximum((D * D).sum(1), 1e-12)
    for k in range(0, len(P), 2048):
        p = P[k:k + 2048, None, :]
        t = np.clip(((p - A[None]) * D[None]).sum(2) / L2[None], 0, 1)
        q = A[None] + D[None] * t[..., None]
        best[k:k + 2048] = np.sqrt(((q - p) ** 2).sum(2)).min(1)
    return best


class Roads:
    """BeamNG.Earth's drivable roads round a line, as a graph: a node per vertex (merged within 0.5 m), an edge per
    piece between two vertices, weighted by its length and how far it is from the line."""

    def __init__(self, np, md, mapcells, frame, line_xy):
        self.np = np
        lat_lon = [frame.latlon(x, y) for x, y in line_xy]
        keys = set()
        pad = CORRIDOR_M + 200
        for lat, lon in lat_lon[::2] + [lat_lon[-1]]:
            x, y = frame.xy(lat, lon)
            for dx in (-pad, 0, pad):
                for dy in (-pad, 0, pad):
                    keys.add(mapcells.cell_of(*frame.latlon(x + dx, y + dy)))
        self.cells = len(keys)
        feats = {}
        for k in sorted(keys):
            r = md.cell(k, layers=('roads',)).layers['roads']
            sub, cls = r.attrs.get('subtype'), r.attrs.get('class')
            for i in range(len(r)):
                if sub is not None and str(sub[i]) != 'road':
                    continue
                if cls is not None and str(cls[i]) in NOT_ROADS:
                    continue
                fid = str(r.ids[i])
                for part in r.parts(i):
                    for ring in part:
                        # (every piece: a road crossing a cell's edge may come clipped in each cell; exact copies once)
                        if len(ring) >= 2:
                            key = (fid, len(ring), round(float(ring[0][0]), 7), round(float(ring[0][1]), 7),
                                   round(float(ring[-1][0]), 7), round(float(ring[-1][1]), 7))
                            feats.setdefault(key, (str(cls[i]) if cls is not None else '?', ring))
        A = np.array(line_xy)
        self.node_xy, self.adj = [], {}
        self.node_near = []     # each node's distance from the organisers' line
        ids = {}

        def node(x, y):
            # (one node for vertices within MERGE_M of each other: roads meeting at a junction, a road's two clipped
            # pieces at a cell's edge)
            gx, gy = math.floor(x / MERGE_M), math.floor(y / MERGE_M)
            for kx in (gx - 1, gx, gx + 1):
                for ky in (gy - 1, gy, gy + 1):
                    for n in ids.get((kx, ky), ()):
                        if math.dist(self.node_xy[n], (x, y)) <= MERGE_M:
                            return n
            n = len(self.node_xy)
            self.node_xy.append((x, y))
            self.node_near.append(math.inf)
            self.adj[n] = []
            ids.setdefault((gx, gy), []).append(n)
            return n

        pieces = []
        for cls, ring in feats.values():
            xy = [frame.xy(la, lo) for lo, la in ring]
            # (no piece longer than PIECE_M: each is weighted by where it lies, and a long straight running past the
            # end of the line is not taken as far off it)
            dense = [xy[0]]
            for a, b in zip(xy, xy[1:]):
                n = max(1, math.ceil(math.dist(a, b) / PIECE_M))
                for k in range(1, n + 1):
                    dense.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
            pieces.append((cls, np.array(dense)))
        if not pieces:
            self.edges = 0
            return
        allp = np.concatenate([p for _, p in pieces])
        near = seg_dist(np, allp, A[:-1], A[1:])
        k = 0
        self.edges = 0
        for cls, xy in pieces:
            d = near[k:k + len(xy)]
            k += len(xy)
            if d.min() > CORRIDOR_M:
                continue
            prev = node(*xy[0])
            self.node_near[prev] = min(self.node_near[prev], float(d[0]))
            for j in range(1, len(xy)):
                cur = node(*xy[j])
                self.node_near[cur] = min(self.node_near[cur], float(d[j]))
                if cur == prev:
                    continue
                dm = (d[j - 1] + d[j]) / 2
                if dm <= CORRIDOR_M:
                    length = math.dist(self.node_xy[prev], self.node_xy[cur])
                    w = length * (1 + (dm / NEAR_M) ** 2)
                    self.adj[prev].append((cur, w, length))
                    self.adj[cur].append((prev, w, length))
                    self.edges += 1
                prev = cur
        self.xy = np.array(self.node_xy)
        # dead ends within BRIDGE_M of another road joined to it (a junction drawn a little apart)
        G = BRIDGE_ON_LINE_M
        grid = {}
        for n, (x, y) in enumerate(self.node_xy):
            grid.setdefault((math.floor(x / G), math.floor(y / G)), []).append(n)
        for n, lst in list(self.adj.items()):
            if len(lst) != 1:
                continue
            x, y = self.node_xy[n]
            gx, gy = math.floor(x / G), math.floor(y / G)
            linked = {m for m, _, _ in lst}
            on_line = self.node_near[n] <= ON_LINE_M
            best, bd = None, math.inf
            for kx in (gx - 1, gx, gx + 1):
                for ky in (gy - 1, gy, gy + 1):
                    for m in grid.get((kx, ky), ()):
                        if m != n and m not in linked:
                            d = math.dist(self.node_xy[m], (x, y))
                            reach = G if (on_line and self.node_near[m] <= ON_LINE_M) else BRIDGE_M
                            if d <= reach and d < bd:
                                best, bd = m, d
            if best is not None:
                self.adj[n].append((best, bd * 2, bd))
                self.adj[best].append((n, bd * 2, bd))
                self.edges += 1
        # (the edges for snapping: every (a, b) once)
        ea, eb = [], []
        for a, lst in self.adj.items():
            for b, _, _ in lst:
                if a < b:
                    ea.append(a)
                    eb.append(b)
        self.ea, self.eb = np.array(ea, dtype=np.int64), np.array(eb, dtype=np.int64)

    def snap(self, p, direction):
        """The road point nearest p within SNAP_M on an edge not across `direction` (more than ~60 degrees off):
        (a, b, t, point) or None."""
        np = self.np
        if self.edges == 0:
            return None
        A, B = self.xy[self.ea], self.xy[self.eb]
        D = B - A
        L2 = np.maximum((D * D).sum(1), 1e-12)
        t = np.clip(((np.array(p) - A) * D).sum(1) / L2, 0, 1)
        Q = A + D * t[:, None]
        d = np.sqrt(((Q - np.array(p)) ** 2).sum(1))
        cos = np.abs((D * np.array(direction)).sum(1)) / np.sqrt(L2) / max(1e-9, math.hypot(*direction))
        # (any road very close; further out only one running the line's way)
        d = np.where((cos >= 0.5) | (d <= 8.0), d, np.inf)
        i = int(d.argmin())
        if not np.isfinite(d[i]) or d[i] > SNAP_M:
            return None
        return int(self.ea[i]), int(self.eb[i]), float(t[i]), (float(Q[i][0]), float(Q[i][1]))

    def route(self, s, g):
        """Cheapest way from snap s to snap g (A*): the polyline and its length, or (None, None)."""
        a0, b0, t0, p0 = s
        a1, b1, t1, p1 = g
        if {a0, b0} == {a1, b1}:
            return [p0, p1], math.dist(p0, p1)
        START, GOAL = -1, -2
        extra = {START: [], GOAL: []}

        def w_of(a, b):
            for n, w, L in self.adj[a]:
                if n == b:
                    return w / max(L, 1e-9)
            return 1.0

        k0 = w_of(a0, b0)
        extra[START] = [(a0, k0 * math.dist(p0, self.node_xy[a0])), (b0, k0 * math.dist(p0, self.node_xy[b0]))]
        k1 = w_of(a1, b1)
        into_goal = {a1: k1 * math.dist(p1, self.node_xy[a1]), b1: k1 * math.dist(p1, self.node_xy[b1])}
        gx, gy = p1

        def h(n):
            x, y = self.node_xy[n]
            return math.hypot(x - gx, y - gy)

        best = {START: 0.0}
        came = {}
        heap = [(0.0, 0.0, START)]
        while heap:
            f, g_, n = heapq.heappop(heap)
            if n == GOAL:
                break
            if g_ > best.get(n, math.inf):
                continue
            nbrs = extra[START] if n == START else [(m, w) for m, w, _ in self.adj[n]]
            if n in into_goal:
                nbrs = list(nbrs) + [(GOAL, into_goal[n])]
            for m, w in nbrs:
                ng = g_ + w
                if ng < best.get(m, math.inf):
                    best[m] = ng
                    came[m] = n
                    heapq.heappush(heap, (ng + (0 if m == GOAL else h(m)), ng, m))
        if GOAL not in came:
            return None, None
        path = []
        n = GOAL
        while n != START:
            n = came[n]
            if n != START:
                path.append(n)
        path.reverse()
        pts = [p0] + [self.node_xy[n] for n in path] + [p1]
        return pts, sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def match_stage(np, md, mapcells, dem, stage):
    line = stage['line']
    frame = Frame(line[0][0], line[0][1])
    kml = [frame.xy(la, lo) for la, lo in line]
    t0 = time.time()
    roads = Roads(np, md, mapcells, frame, kml)
    wps, along = resample(kml, WAYPOINT_M)
    fine, fine_along = resample(kml, 5.0)

    def tangent(s):
        # the line's direction at s (over 20 m: its points can be far apart, so this is the drawn segment's way)
        i0 = min(range(len(fine)), key=lambda k: abs(fine_along[k] - (s - 10)))
        i1 = min(range(len(fine)), key=lambda k: abs(fine_along[k] - (s + 10)))
        if i1 == i0:
            i1 = min(len(fine) - 1, i0 + 1)
            i0 = max(0, i1 - 1)
        return fine[i1][0] - fine[i0][0], fine[i1][1] - fine[i0][1]

    # each waypoint on a road beside it, aligned with the line there
    snaps = [roads.snap(p, tangent(along[i])) for i, p in enumerate(wps)]
    out, gaps = [], []
    kml_cum = [0.0]
    for a, b in zip(kml, kml[1:]):
        kml_cum.append(kml_cum[-1] + math.dist(a, b))

    def kml_between(s0, s1):
        return [p for p, s in zip(fine, fine_along) if s0 <= s <= s1]

    def add(pts):
        for p in pts:
            if not out or math.dist(out[-1], p) > 0.05:
                out.append(p)

    i = 0
    n = len(wps)
    while i < n - 1:
        if snaps[i] is None:
            # no road near this waypoint: the organisers' line up to the next waypoint on a road
            j = i + 1
            while j < n - 1 and snaps[j] is None:
                j += 1
            s0, s1 = along[i], along[j]
            gaps.append((s0, s1))
            add(kml_between(s0, s1))
            i = j
            continue
        j = i + 1
        if snaps[j] is None:
            # (the next one has no road: go straight on along the organisers' line from here)
            k = j
            while k < n - 1 and snaps[k] is None:
                k += 1
            gaps.append((along[i], along[k]))
            add([snaps[i][3]])
            add(kml_between(along[i], along[k]))
            i = k
            continue
        pts, length = roads.route(snaps[i], snaps[j])
        span = along[j] - along[i]
        if pts is None or length > DETOUR_MAX * span + 100:
            gaps.append((along[i], along[j]))
            add([snaps[i][3]])
            add(kml_between(along[i], along[j]))
        else:
            add(pts)
        i = j
    if not out:
        return None
    # the matched line every OUT_STEP_M, with heights
    res, _ = resample(out, OUT_STEP_M)
    lat_lon = [frame.latlon(x, y) for x, y in res]
    lats = np.array([p[0] for p in lat_lon])
    lons = np.array([p[1] for p in lat_lon])
    z = dem.sample(lats, lons, 16) + HEIGHT_OFFSET_M
    total = sum(math.dist(a, b) for a, b in zip(res, res[1:]))
    off_line = seg_dist(np, np.array(res), np.array(kml[:-1]), np.array(kml[1:]))
    gap_m = sum(b - a for a, b in gaps)
    return {
        'format': 1, 'stage': stage['id'], 'source': "BeamNG.Earth's roads (tools/match_roads.py)",
        'date': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'lengthM': round(total, 1), 'mapLineM': round(kml_cum[-1], 1),
        'gaps': [[round(a, 1), round(b, 1)] for a, b in gaps], 'gapM': round(gap_m, 1),
        'maxOffMapLineM': round(float(off_line.max()), 1),
        'cells': roads.cells, 'roadEdges': roads.edges, 'seconds': round(time.time() - t0, 1),
        'points': [[round(la, 7), round(lo, 7), round(float(h), 2)] for (la, lo), h in zip(lat_lon, z)],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--earth', required=True, help="BeamNG.Earth's source folder (with server/)")
    ap.add_argument('--event', required=True, help="the event's id (its file in earthRally/events)")
    ap.add_argument('--stage', help='one stage only (its id)')
    ap.add_argument('--user-dir', default=user_dir())
    ap.add_argument('--cache-dir', default=os.path.expanduser('~/.cache/beamng-earth'),
                    help="BeamNG.Earth's download cache (its default)")
    args = ap.parse_args()
    sys.path.insert(0, os.path.join(args.earth, 'server'))
    import logging
    logging.basicConfig(level=logging.WARNING)
    import numpy as np
    import mapdata
    import mapcells
    import dem as demmod
    md = mapdata.MapData(args.cache_dir)
    dem = demmod.Dem(args.cache_dir)
    with open(os.path.join(args.user_dir, 'earthRally', 'events', args.event + '.json'), encoding='utf-8') as f:
        event = json.load(f)
    out_dir = os.path.join(args.user_dir, 'earthRally', 'matched')
    os.makedirs(out_dir, exist_ok=True)
    for stage in event['stages']:
        if args.stage and stage['id'] != args.stage:
            continue
        m = match_stage(np, md, mapcells, dem, stage)
        if not m:
            print(f"{stage['id']:<45} no roads found")
            continue
        path = os.path.join(out_dir, f"{event['id']}__{stage['id']}.json")
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(m, f)
        print(f"{stage['id']:<45} {m['lengthM'] / 1000:5.1f} km (map line {m['mapLineM'] / 1000:5.1f}), "
              f"no road on the map for {m['gapM']:.0f} m in {len(m['gaps'])} stretch(es), "
              f"{m['seconds']:.0f} s")
    return 0


if __name__ == '__main__':
    sys.exit(main())

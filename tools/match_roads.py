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
BLEND_M = 120.0         # a stretch on the organisers' line eased into the road over this at each end
BRIDGE_M = 3.0          # a dead end this close to another road is joined to it ...
BRIDGE_ON_LINE_M = 25.0 # ... or this close when both lie on the organisers' line (within ON_LINE_M): a break in the
ON_LINE_M = 12.0        # map's road where the stage plainly goes on
OUT_STEP_M = 4.0        # the matched line's point spacing (as a recce's)
HEIGHT_OFFSET_M = 0.2   # a recce's heights (the car's position) sit this far above the elevation data
JUNCTION_LOOK_M = 15.0  # a junction's roads: their way this far from it
SIDE_ROAD_MIN_M = 40.0  # a side road shorter than this (a dead end: a driveway, a stub of track) is no junction
TURN_DEG = 30.0         # the stage turning more than this at a junction: a turn there ("at junction")
FORK_DEG = 35.0         # a side road within this of the stage's way on: a fork ("keep left / right")
JUNCTION_GAP_M = 25.0   # junctions closer than this along the stage: one
BRIDGE_NEAR_M = 3.0     # the stage this close to a bridge's road ...
BRIDGE_MIN_M = 6.0      # ... for at least this far: over the bridge (a road crossing under one is near it for less)
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
    # (the line's own end always: dropping it when near the last point cut matched lines up to a quarter step short of
    # the flying finish, 83 m on Maryhill: review 2026-11-12)
    if math.dist(out[-1], xy[-1]) > 0.5:
        out.append(xy[-1])
        along.append(acc)
    return out, along


def _sub_ring(ring, a, b):
    """The part of a ring (lon, lat points) from fraction a to b of its length (flat lengths: short pieces)."""
    pts = [(float(p[0]), float(p[1])) for p in ring]
    cum = [0.0]
    for p, q in zip(pts, pts[1:]):
        cum.append(cum[-1] + math.dist(p, q))
    total = cum[-1]
    if total <= 0:
        return pts[:1]

    def at(f):
        s = f * total
        for k in range(1, len(pts)):
            if cum[k] >= s:
                t = (s - cum[k - 1]) / max(cum[k] - cum[k - 1], 1e-12)
                return (pts[k - 1][0] + (pts[k][0] - pts[k - 1][0]) * t, pts[k - 1][1] + (pts[k][1] - pts[k - 1][1]) * t)
        return pts[-1]
    out = [at(a)] + [p for p, c in zip(pts, cum) if a * total < c < b * total] + [at(b)]
    return out


def _angle(u, v):
    """The signed angle from u to v (degrees, + to the left)."""
    return math.degrees(math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1]))


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

    def __init__(self, np, md, mapcells, frame, line_xy, roadsmod=None):
        self.np = np
        self.bridges = []       # each bridge's deck as a polyline (frame xy), from BeamNG.Earth's level ranges
        keys = set()
        pad = CORRIDOR_M + 200
        along_line, _ = resample(line_xy, 200.0)
        for x, y in along_line:
            for dx in (-pad, 0, pad):
                for dy in (-pad, 0, pad):
                    keys.add(mapcells.cell_of(*frame.latlon(x + dx, y + dy)))
        self.cells = len(keys)
        feats = {}
        for k in sorted(keys):
            r = md.cell(k, layers=('roads',)).layers.get('roads')
            if r is None:           # (no road data for that cell: none there to use)
                continue
            sub, cls = r.attrs.get('subtype'), r.attrs.get('class')
            for i in range(len(r)):
                if sub is not None and str(sub[i]) != 'road':
                    continue
                if cls is not None and str(cls[i]) in NOT_ROADS:
                    continue
                fid = str(r.ids[i])
                spans = []
                if roadsmod is not None:
                    try:
                        spans = [(a, b) for a, b, k in roadsmod.level_ranges(r, i) if k == 'bridge']
                    except Exception:       # (no level data: no bridges known here)
                        spans = []
                for part in r.parts(i):
                    for ring in part:
                        for a, b in spans:
                            self.bridges.append([frame.xy(la, lo) for lo, la in _sub_ring(ring, a, b)])
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

    def neighbours(self, n):
        return {m for m, _, _ in self.adj.get(n, ())}

    def branch(self, n, m):
        """Walking from node n through m, the road turning least at each node: its way at JUNCTION_LOOK_M from n, and
        how far it goes (up to SIDE_ROAD_MIN_M; less at a dead end)."""
        prev, cur, dist = n, m, math.dist(self.node_xy[n], self.node_xy[m])
        x0, y0 = self.node_xy[n]
        way = None
        while True:
            if way is None and dist >= JUNCTION_LOOK_M:
                x, y = self.node_xy[cur]
                way = (x - x0, y - y0)
            if dist >= SIDE_ROAD_MIN_M:
                break
            h = (self.node_xy[cur][0] - self.node_xy[prev][0], self.node_xy[cur][1] - self.node_xy[prev][1])
            nxt = [k for k in self.neighbours(cur) if k != prev]
            if not nxt:
                break
            best = min(nxt, key=lambda k: abs(_angle(h, (self.node_xy[k][0] - self.node_xy[cur][0],
                                                          self.node_xy[k][1] - self.node_xy[cur][1]))))
            prev, cur = cur, best
            dist += math.dist(self.node_xy[prev], self.node_xy[cur])
        if way is None:
            x, y = self.node_xy[cur]
            way = (x - x0, y - y0)
        return way, dist

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


def landmarks(np, roads, res, res_along, flags):
    """The junctions and bridges along the matched line (res, every OUT_STEP_M; flags: 1 on a stretch with no road).
    Junctions: [(along, kind, side)] with kind 'turn' (the stage turns there), 'straight' (on past a side road) or
    'fork' (side: 'left' / 'right', the way the stage keeps); bridges: [(from, to)] along the line."""
    juncs, bridges = [], []
    if roads.edges == 0 or len(res) < 3:
        return juncs, bridges
    P = np.array(res)
    # junctions: nodes with 3+ roads, on the line (not on a stretch with no road)
    deg3 = [n for n, lst in roads.adj.items() if len({m for m, _, _ in lst}) >= 3]
    if deg3:
        XY = np.array([roads.node_xy[n] for n in deg3])
        on_line = seg_dist(np, XY, P[:-1], P[1:]) <= 1.5      # (on the line itself, not only near its points)
        last = -math.inf
        cand = []
        for n, (x, y), ok in zip(deg3, XY, on_line):
            if not ok:
                continue
            d = np.hypot(P[:, 0] - x, P[:, 1] - y)
            k = int(d.argmin())
            if flags[k] or k < 1 or k >= len(res) - 1:
                continue
            cand.append((res_along[k], n, x, y, k))
        cand.sort()
        for _s, n, x, y, k in cand:
            look = max(1, int(JUNCTION_LOOK_M / OUT_STEP_M))
            a, b = res[max(0, k - look)], res[min(len(res) - 1, k + look)]
            w_in = (x - a[0], y - a[1])
            w_out = (b[0] - x, b[1] - y)
            ways = [(m, roads.branch(n, m)) for m in roads.neighbours(n)]
            # the stage's own two roads: the one it comes in on and the one it leaves by
            back = (-w_in[0], -w_in[1])
            m_in = min(ways, key=lambda t: abs(_angle(back, t[1][0])))[0]
            m_out = min((t for t in ways if t[0] != m_in), key=lambda t: abs(_angle(w_out, t[1][0])))[0]
            sides = [w for m, (w, length) in ways if m not in (m_in, m_out) and length >= SIDE_ROAD_MIN_M]
            if not sides:
                continue
            s = res_along[k]
            turn = _angle(w_in, w_out)
            if abs(turn) >= TURN_DEG:
                kind, side = 'turn', ''
            else:
                close = [w for w in sides if abs(_angle(w_out, w)) < FORK_DEG]
                if close:
                    # (our way to the left of the other road: keep left)
                    kind, side = 'fork', 'left' if _angle(close[0], w_out) > 0 else 'right'
                else:
                    kind, side = 'straight', ''
            if s - last < JUNCTION_GAP_M:
                continue
            last = s
            juncs.append((s, kind, side))
    # bridges: the line along a bridge's deck for BRIDGE_MIN_M or more
    on = np.zeros(len(res), dtype=bool)
    for deck in roads.bridges:
        if len(deck) < 2:
            continue
        D = np.array(deck)
        on |= seg_dist(np, P, D[:-1], D[1:]) <= BRIDGE_NEAR_M
    k = 0
    while k < len(res):
        if on[k] and not flags[k]:
            j = k
            while j + 1 < len(res) and on[j + 1]:
                j += 1
            if res_along[j] - res_along[k] >= BRIDGE_MIN_M:
                bridges.append((res_along[k], res_along[j]))
            k = j + 1
        else:
            k += 1
    return juncs, bridges


def match_stage(np, md, mapcells, dem, stage, roadsmod=None):
    line = stage['line']
    frame = Frame(line[0][0], line[0][1])
    kml = [frame.xy(la, lo) for la, lo in line]
    t0 = time.time()
    roads = Roads(np, md, mapcells, frame, kml, roadsmod)
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

    gap_idx = []        # (first, last) indices into out of each stretch on the organisers' line

    def add(pts):
        for p in pts:
            if not out or math.dist(out[-1], p) > 0.05:
                out.append(p)

    def add_gap(s0, s1, from_pt=None, to_pt=None):
        # the organisers' line from s0 to s1, eased in from the road point before it and out to the road point after
        # it over BLEND_M (no sudden kink where a hand-drawn line meets the road: that would be a phantom hairpin)
        pts = kml_between(s0, s1)
        if not pts:
            return
        o0 = (from_pt[0] - pts[0][0], from_pt[1] - pts[0][1]) if from_pt else (0.0, 0.0)
        o1 = (to_pt[0] - pts[-1][0], to_pt[1] - pts[-1][1]) if to_pt else (0.0, 0.0)
        acc, eased = 0.0, []
        total = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
        for k, p in enumerate(pts):
            if k:
                acc += math.dist(pts[k - 1], p)
            w0 = max(0.0, 1 - acc / BLEND_M)
            w1 = max(0.0, 1 - (total - acc) / BLEND_M)
            eased.append((p[0] + o0[0] * w0 + o1[0] * w1, p[1] + o0[1] * w0 + o1[1] * w1))
        first = len(out)
        add(eased)
        gap_idx.append((first, len(out) - 1))

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
            add_gap(s0, s1, out[-1] if out else None, snaps[j][3] if snaps[j] else None)
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
            add_gap(along[i], along[k], snaps[i][3], snaps[k][3] if snaps[k] else None)
            i = k
            continue
        pts, length = roads.route(snaps[i], snaps[j])
        span = along[j] - along[i]
        if pts is None or length > DETOUR_MAX * span + 100:
            gaps.append((along[i], along[j]))
            add([snaps[i][3]])
            add_gap(along[i], along[j], snaps[i][3], snaps[j][3])
        else:
            add(pts)
        i = j
    if not out:
        return None
    # the matched line every OUT_STEP_M, with heights; the points on a stretch with no road flagged (the mod calls no
    # notes there)
    out_cum = [0.0]
    for a, b in zip(out, out[1:]):
        out_cum.append(out_cum[-1] + math.dist(a, b))
    gap_ranges = [(out_cum[a], out_cum[b]) for a, b in gap_idx]
    res, res_along = resample(out, OUT_STEP_M)
    flags = [1 if any(g0 <= s <= g1 for g0, g1 in gap_ranges) else 0 for s in res_along]
    lat_lon = [frame.latlon(x, y) for x, y in res]
    juncs, bridges = landmarks(np, roads, res, res_along, flags)

    def ll(s):
        k = min(len(res_along) - 1, max(0, int(round(s / OUT_STEP_M))))
        return [round(lat_lon[k][0], 7), round(lat_lon[k][1], 7)]
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
        'mapKey': map_key(stage['line']),
        # (where they are on the road, as lat / lon: the mod finds them on whichever line the stage runs on, a recce's too)
        'junctions': [ll(s) + [kind, side] for s, kind, side in juncs],
        'bridges': [ll(a) + ll(b) for a, b in bridges],
        'points': [[round(la, 7), round(lo, 7), round(float(h), 2)] + ([1] if f else [])
                   for (la, lo), h, f in zip(lat_lon, z, flags)],
    }


def map_key(line):
    """The stage's map line in short, as the mod's events.mapKey: a matched line from another version of the map is
    not used."""
    a, b = line[0], line[-1]
    return '%d:%.6f:%.6f:%.6f:%.6f' % (len(line), a[0], a[1], b[0], b[1])


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
    import roads as roadsmod
    md = mapdata.MapData(args.cache_dir)
    # the dem sub-folder, not the cache root: Dem lays its tiles out as <dir>/<source>/<z>/<x>/<y>, and the server
    # gives it `<cache>/dem` (earthd.py). Passing the root made it look for tiles that were never there and fetch
    # every one again -- 0 of 14,376 already-downloaded tiles seen on this machine (measured, 2026-11-13).
    dem = demmod.Dem(os.path.join(args.cache_dir, 'dem'))
    with open(os.path.join(args.user_dir, 'earthRally', 'events', args.event + '.json'), encoding='utf-8') as f:
        event = json.load(f)
    out_dir = os.path.join(args.user_dir, 'earthRally', 'matched')
    os.makedirs(out_dir, exist_ok=True)
    for stage in event['stages']:
        if args.stage and stage['id'] != args.stage:
            continue
        m = match_stage(np, md, mapcells, dem, stage, roadsmod)
        if not m:
            print(f"{stage['id']:<45} no roads found")
            continue
        path = os.path.join(out_dir, f"{event['id']}__{stage['id']}.json")
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(m, f)
        print(f"{stage['id']:<45} {m['lengthM'] / 1000:5.1f} km (map line {m['mapLineM'] / 1000:5.1f}), "
              f"no road on the map for {m['gapM']:.0f} m in {len(m['gaps'])} stretch(es), "
              f"{len(m['junctions'])} junction(s), {len(m['bridges'])} bridge(s), "
              f"{m['seconds']:.0f} s")
    return 0


if __name__ == '__main__':
    sys.exit(main())

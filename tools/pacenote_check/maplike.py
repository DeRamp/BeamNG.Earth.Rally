"""A clean game driveline made to look like a stage line off the map: the road as BeamNG.Earth's road graph gives it
(points where the road bends, one edge along a straight, heights only at those points), then resampled every 4 m as
the auto recce writes a matched line (autoRecce.OUT_STEP_M) and rounded as the file stores it (7 decimals of lat /
lon, 1 cm of height). Lets the pipeline be scored against the game's own notes on roads drawn the way the player's
are.

TOL_M was set from the owner's 31 matched stages (2026-11-20, docs/pacenote-check.md "Map point spacing"): the
road graph's points, found again in a matched line with a 5 cm Douglas-Peucker, sit (weighted by length) every
4 / 4 / 8 / 28 / 68 m in bends (10th / 25th / 50th / 75th / 90th percentile) and 4 / 16 / 28 / 60 / 124 m elsewhere.
A clean driveline thinned at 0.6 m gives 4 / 4 / 12 / 28 / 48 and 4 / 12 / 28 / 56 / 96: the nearest of the
tolerances tried (0.1 - 0.8 m). Pure Python."""
import math

TOL_M = 0.6           # Douglas-Peucker tolerance: how far the map's polyline may cut inside the road
STEP_M = 4.0          # the matched line's spacing
ROUND_XY_M = 0.011    # 7 decimals of latitude
ROUND_Z_M = 0.01


def dp(pts, tol):
    """Indices of the points a Douglas-Peucker simplification at `tol` (m, in plan) keeps."""
    n = len(pts)
    if n < 3:
        return list(range(n))
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a][0], pts[a][1]
        dx, dy = pts[b][0] - ax, pts[b][1] - ay
        L = math.hypot(dx, dy) or 1e-9
        best, bi = -1.0, None
        for i in range(a + 1, b):
            d = abs((pts[i][0] - ax) * dy - (pts[i][1] - ay) * dx) / L
            if d > best:
                best, bi = d, i
        if bi is not None and best > tol:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [i for i, k in enumerate(keep) if k]


def resample(pts, step):
    out = [tuple(pts[0])]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a[:2], b[:2])
        pos = step - carry
        while pos <= seg:
            t = pos / seg
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
            pos += step
        carry = seg - (pos - step)
    if math.dist(out[-1][:2], pts[-1][:2]) > 1e-6:
        out.append(tuple(pts[-1]))
    return out


def _jitter(i, k):
    # a fixed pseudo-random offset in [-0.5, 0.5): the file's rounding, the same on every run
    v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v) - 0.5


def degrade(line, tol=TOL_M):
    """line: [{x, y, z}] (a clean driveline, about every metre) -> the same road as a matched line: [{x, y, z}]."""
    pts = [(p['x'], p['y'], p['z']) for p in line]
    keep = dp(pts, tol)
    res = resample([pts[i] for i in keep], STEP_M)
    out = []
    for i, (x, y, z) in enumerate(res):
        out.append({'x': x + _jitter(i, 1) * ROUND_XY_M, 'y': y + _jitter(i, 2) * ROUND_XY_M,
                    'z': round(z / ROUND_Z_M) * ROUND_Z_M})
    return out


def degrade_xy_only(line, tol=TOL_M):
    """The map's plan, but the heights of the clean line (as a ground ray every few metres would give them)."""
    m = degrade(line, tol)
    zs = [(p['x'], p['y'], p['z']) for p in line]
    j = 0
    for p in m:
        best = 1e18
        k0 = max(0, j - 20)
        for k in range(k0, min(len(zs), j + 200)):
            d = (zs[k][0] - p['x']) ** 2 + (zs[k][1] - p['y']) ** 2
            if d < best:
                best, j = d, k
        p['z'] = zs[j][2]
    return m

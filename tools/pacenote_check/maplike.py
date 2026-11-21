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


# autoRecce.lua's ground rays (M.RAY_*), as shipped: the same spacing, pick and blend
RAY_STEP_M = 4.0
RAY_SNAP_M = 3.0
RAY_GRADE = 0.3
RAY_AGREE_M = 0.5
RAY_BLEND_N = 4
RAY_MAX_OFF_M = 15


def pick_rays(cands, za, zb, ds):
    """autoRecce.pickRays: the road's ground along an edge, walked from both ends."""
    n = len(cands)

    def walk(order, z0):
        out, prev, gap = {}, z0, 1
        for i in order:
            best = min(cands[i], key=lambda z: abs(z - prev)) if cands[i] else None
            if best is not None and abs(best - prev) <= RAY_GRADE * ds * gap:
                out[i], prev, gap = best, best, 1
            else:
                gap += 1
        return out
    f, b = walk(range(n), za), walk(range(n - 1, -1, -1), zb)
    return {i: f[i] for i in f if i in b and abs(f[i] - b[i]) <= RAY_AGREE_M}


def degrade_rays(line, tol=TOL_M):
    """The map-like line with its heights as the auto recce's ground rays give them in game: rays every RAY_STEP_M
    along each map edge (the clean line's height under each), kept by autoRecce.pickRays, then graph + the smoothed
    offset (autoRecce.rayHeights). The clean line has no trees or bridges, so this models coverage and blending."""
    pts = [(p['x'], p['y'], p['z']) for p in line]
    keep = dp(pts, tol)
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + math.dist(a[:2], b[:2]))

    def z_at(i0, i1, t):
        # the clean line's height at fraction t along the map edge from kept point i0 to i1 (by distance along)
        target = cum[i0] + (cum[i1] - cum[i0]) * t
        k = i0
        while k < i1 and cum[k + 1] < target:
            k += 1
        if k >= i1:
            return pts[i1][2]
        seg = cum[k + 1] - cum[k]
        u = (target - cum[k]) / seg if seg > 1e-9 else 0
        return pts[k][2] + (pts[k + 1][2] - pts[k][2]) * u
    rays = []
    for i0, i1 in zip(keep, keep[1:]):
        a, b = pts[i0], pts[i1]
        L = math.dist(a[:2], b[:2])
        n = int(L // RAY_STEP_M)
        if n < 2:
            continue
        at = [(a[0] + (b[0] - a[0]) * q / n, a[1] + (b[1] - a[1]) * q / n) for q in range(1, n)]
        cands = [[z_at(i0, i1, q / n)] for q in range(1, n)]
        for q, z in pick_rays(cands, a[2], b[2], L / n).items():
            rays.append((at[q][0], at[q][1], z))
    m = degrade(line, tol)
    cell = RAY_SNAP_M
    grid = {}
    for x, y, z in rays:
        grid.setdefault((math.floor(x / cell), math.floor(y / cell)), []).append((x, y, z))
    off = {}
    for k, p in enumerate(m):
        cx, cy = math.floor(p['x'] / cell), math.floor(p['y'] / cell)
        best, bz = RAY_SNAP_M ** 2, None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for x, y, z in grid.get((cx + dx, cy + dy), ()):
                    d = (x - p['x']) ** 2 + (y - p['y']) ** 2
                    if d <= best:
                        best, bz = d, z
        if bz is not None and abs(bz - p['z']) <= RAY_MAX_OFF_M:
            off[k] = bz - p['z']
    w, sigma = RAY_BLEND_N, max(0.5, RAY_BLEND_N / 2)
    new = []
    for k, p in enumerate(m):
        s_, ws = 0.0, 0.0
        for d in range(-w, w + 1):
            if 0 <= k + d < len(m):
                wt = math.exp(-0.5 * (d / sigma) ** 2)
                s_, ws = s_ + wt * off.get(k + d, 0.0), ws + wt
        new.append(p['z'] + s_ / ws)
    for p, z in zip(m, new):
        p['z'] = round(z / ROUND_Z_M) * ROUND_Z_M
    return m


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


def degrade_driven(line, wander_m=0.3, noise_m=0.05):
    """The road as a driven recce gives it: the car's position every STEP_M, wandering across the road (sines of
    40-150 m, wander_m) with noise_m of jitter. Not a map line: the check of the curve fit on dense lines."""
    pts = [(p['x'], p['y'], p['z']) for p in line]
    res = resample(pts, STEP_M)
    out = []
    s = 0.0
    for i, (x, y, z) in enumerate(res):
        if i:
            s += math.dist(res[i - 1][:2], (x, y))
        a, b = res[max(0, i - 1)], res[min(len(res) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / L, dx / L
        off = wander_m * (0.6 * math.sin(s / 150 * 2 * math.pi) + 0.4 * math.sin(s / 41 * 2 * math.pi + 1.3)) +             noise_m * 2 * _jitter(i, 3)
        out.append({'x': x + nx * off, 'y': y + ny * off, 'z': z})
    return out


def degrade_trace(line, sigma_m, tol=TOL_M):
    """degrade, with each map point moved sideways by up to about sigma_m (a fixed pseudo-random amount): a map traced
    off the road with wiggle. The check of whether such wiggle makes calls (the owner's matched lines show no more
    wiggle than degrade gives: docs/pacenote-check.md)."""
    pts = [(p['x'], p['y'], p['z']) for p in line]
    keep = dp(pts, tol)
    P = [pts[i] for i in keep]
    moved = []
    for k, (x, y, z) in enumerate(P):
        a, b = P[max(0, k - 1)], P[min(len(P) - 1, k + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1.0
        o = sigma_m * 2 * 1.7 * _jitter(k, 5) if 0 < k < len(P) - 1 else 0.0
        moved.append((x - dy / L * o, y + dx / L * o, z))
    res = resample(moved, STEP_M)
    return [{'x': x + _jitter(i, 1) * ROUND_XY_M, 'y': y + _jitter(i, 2) * ROUND_XY_M,
             'z': round(z / ROUND_Z_M) * ROUND_Z_M} for i, (x, y, z) in enumerate(res)]

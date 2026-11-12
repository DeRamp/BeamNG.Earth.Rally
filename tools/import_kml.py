#!/usr/bin/env python3
"""Import a rally's KML (or GPX) map into an Earth Rally event file.

Each line in the file becomes a stage (pieces stitched together in driving order); the named points next to it
(start, flying finish, stop, ATC / TC) become its controls. Everything else (service, regroups, spectator areas)
is kept as plain points. The result goes to the game's user folder, where the mod reads it:

    <BeamNG user folder>/current/earthRally/events/<event id>.json

    python tools/import_kml.py "Rally Docs/V4 Olympus Rally 26.kml"
    python tools/import_kml.py "Rally Docs/OTR 2024 Final.kml" --id otr24 --name "Oregon Trail Rally 2024"
    python tools/import_kml.py FILE --out some/folder        (anywhere else)

The KML lines are only a guide to which roads a stage uses: they are hand-drawn and cut corners, so the mod drives
a recce first and times stages on the line it recorded. Organisers' maps stay on your computer: the event files are
written outside this repository, and Rally Docs/ is in .gitignore.
"""

import argparse
import json
import math
import os
import random
import re
import sys
import xml.etree.ElementTree as ET

FORMAT = 1
R_EARTH = 6371008.8
GAP_WARN_M = 50.0          # a gap between two stitched pieces worth reporting
ROLE_WORDS = {             # point name word -> control role
    'start': 'start', 'ss': 'start',
    'ff': 'ff', 'flying': 'ff', 'finish': 'ff',
    'stop': 'stop',
    'atc': 'atc', 'tc': 'atc',
}
ROLE_SKIP = {'control', 'end', 'in', 'out'}   # words of a control's name that are not the stage's name
OTHER_WORDS = {'spectator', 'jump', 'vc', 'barricade', 'service', 'regroup', 'mtc', 'parc', 'maybe', 'area',
               'traffic', 'prohibited', 'expose'}


# --------------------------------------------------------------------------------------------------- geometry

class Frame:
    """A local flat frame (metres east / north) round a point: plenty for stages tens of km long."""

    def __init__(self, lat, lon):
        self.lat0, self.lon0 = lat, lon
        self.kx = math.radians(1) * R_EARTH * math.cos(math.radians(lat))
        self.ky = math.radians(1) * R_EARTH

    def xy(self, lat, lon):
        return (lon - self.lon0) * self.kx, (lat - self.lat0) * self.ky

    def latlon(self, x, y):
        return self.lat0 + y / self.ky, self.lon0 + x / self.kx


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def length(xy):
    return sum(dist(xy[i], xy[i + 1]) for i in range(len(xy) - 1))


def project(xy, p):
    """Distance along the line xy of its point nearest p, and how far p is from the line."""
    best, along, acc = None, 0.0, 0.0
    for i in range(len(xy) - 1):
        a, b = xy[i], xy[i + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        seg = math.hypot(dx, dy)
        t = 0.0 if seg < 1e-9 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (seg * seg)))
        d = math.hypot(a[0] + t * dx - p[0], a[1] + t * dy - p[1])
        if best is None or d < best:
            best, along = d, acc + t * seg
        acc += seg
    return along, best


def enclosing_circle(pts):
    """Smallest circle round the points (Welzl, iterative): the stage's centre for the world's anchor."""
    pts = list(pts)
    random.Random(1).shuffle(pts)

    def circle2(a, b):
        c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        return c, dist(a, c)

    def circle3(a, b, c):
        ax, ay, bx, by, cx, cy = *a, *b, *c
        d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        if abs(d) < 1e-12:
            return None
        ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
        uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
        return (ux, uy), dist((ux, uy), a)

    def inside(c, p):
        return c is not None and dist(c[0], p) <= c[1] + 1e-7

    c = None
    for i, p in enumerate(pts):
        if inside(c, p):
            continue
        c = (p, 0.0)
        for j in range(i):
            q = pts[j]
            if inside(c, q):
                continue
            c = circle2(p, q)
            for k in range(j):
                r = pts[k]
                if not inside(c, r):
                    c = circle3(p, q, r) or c
    return c


# --------------------------------------------------------------------------------------------------- reading

def strip_ns(tag):
    return tag.split('}', 1)[-1]


def coords(text):
    out = []
    for tok in (text or '').split():
        parts = tok.split(',')
        if len(parts) >= 2:
            out.append((float(parts[1]), float(parts[0])))     # (lat, lon); KML altitudes are dropped
    return out


def read_kml(path):
    if path.lower().endswith('.kmz'):
        import zipfile
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if n.lower().endswith('.kml')]
            pick = next((n for n in names if n.lower().endswith('doc.kml')), names[0] if names else None)
            if not pick:
                raise SystemExit(f'{path}: no KML inside the .kmz')
            root = ET.fromstring(z.read(pick))
    else:
        root = ET.parse(path).getroot()
    lines, points = [], []
    for pm in root.iter():
        if strip_ns(pm.tag) != 'Placemark':
            continue
        name = ''
        pieces, pts = [], []
        for el in pm.iter():
            t = strip_ns(el.tag)
            if t == 'name' and not name:
                name = (el.text or '').strip()
            elif t == 'LineString':
                for c in el:
                    if strip_ns(c.tag) == 'coordinates':
                        pieces.append(coords(c.text))
            elif t == 'Point':
                for c in el:
                    if strip_ns(c.tag) == 'coordinates':
                        pts.extend(coords(c.text))
        if pieces:
            lines.append((name, [p for p in pieces if len(p) >= 2]))
        elif pts:
            points.append((name, pts[0]))
    return lines, points


def read_gpx(path):
    root = ET.parse(path).getroot()
    lines, points = [], []
    for el in root:
        t = strip_ns(el.tag)
        name = next((strip_ns(c.tag) == 'name' and (c.text or '').strip() for c in el if strip_ns(c.tag) == 'name'), '')
        if t == 'wpt':
            points.append((name, (float(el.get('lat')), float(el.get('lon')))))
        elif t in ('trk', 'rte'):
            pieces = []
            for seg in el.iter():
                st = strip_ns(seg.tag)
                if st in ('trkseg', 'rte') :
                    pts = [(float(p.get('lat')), float(p.get('lon'))) for p in seg
                           if strip_ns(p.tag) in ('trkpt', 'rtept')]
                    if len(pts) >= 2:
                        pieces.append(pts)
            if pieces:
                lines.append((name, pieces))
    return lines, points


# --------------------------------------------------------------------------------------------------- names

def words(name):
    s = name.lower().replace('’', "'").replace('�', "'")
    s = re.sub(r"'s\b", 's', s)
    return [w for w in re.split(r'[^a-z0-9]+', s) if w]


def stage_key(name):
    """The words that name a stage: role words, years, version tags and stage numbers left out ('SS3 Dayton 26 V2' ->
    dayton)."""
    out = []
    for w in words(name):
        if w in ROLE_WORDS or w in ROLE_SKIP:
            continue
        if re.fullmatch(r'\d{2}|\d{4}|v\d+|ss\d+', w):
            continue
        out.append(w)
    return out


def slug(name):
    return '-'.join(stage_key(name)) or 'stage'


def point_role(name):
    ws = words(name)
    if any(w in OTHER_WORDS for w in ws):
        return None
    if 'flying' in ws or 'ff' in ws:
        return 'ff'
    for w in ws:
        if w in ROLE_WORDS:
            return ROLE_WORDS[w]
    return None


def match_controls(stage_names, points):
    """{stage index: {role: (name, lat, lon)}} by name: a control whose remaining words are the stage's name, or the
    start of it when only one stage begins that way ('Maryhill FF' for 'Maryhill Up')."""
    keys = [stage_key(n) for n in stage_names]
    found = {i: {} for i in range(len(stage_names))}
    unmatched = []
    for name, (lat, lon) in points:
        role = point_role(name)
        if not role:
            continue
        k = stage_key(name)
        reverse = 'reverse' in k
        hits = [i for i, sk in enumerate(keys) if sk == k]
        if not hits and k:
            hits = [i for i, sk in enumerate(keys) if sk[:len(k)] == k and ('reverse' in sk) == reverse]
            if len(hits) > 1:
                hits = []
        if len(hits) == 1:
            found[hits[0]].setdefault(role, (name, lat, lon))
        else:
            unmatched.append(name)
    return found, unmatched


# --------------------------------------------------------------------------------------------------- stitching

def stitch(pieces_xy, start_xy=None):
    """One line from the pieces in driving order: from the piece end nearest the start (else the longest piece), each
    next piece the one with an end nearest the line's end, reversed as needed. Returns (line, [gaps m])."""
    pieces = [list(p) for p in pieces_xy]
    if start_xy is not None:
        best = min(((dist(p[e], start_xy), i, e) for i, p in enumerate(pieces) for e in (0, -1)))
        _, i0, e0 = best
    else:
        i0, e0 = max(range(len(pieces)), key=lambda i: length(pieces[i])), 0
    line = pieces.pop(i0)
    if e0 == -1:
        line.reverse()
    gaps = []
    while pieces:
        end = line[-1]
        best = min(((dist(p[e], end), i, e) for i, p in enumerate(pieces) for e in (0, -1)))
        d, i, e = best
        nxt = pieces.pop(i)
        if e == -1:
            nxt.reverse()
        gaps.append(d)
        line.extend(nxt if d > 0.5 else nxt[1:])
    return line, gaps


# --------------------------------------------------------------------------------------------------- event

def build_event(path, event_id, event_name):
    ext = os.path.splitext(path)[1].lower()
    lines, points = (read_gpx if ext == '.gpx' else read_kml)(path)
    if not lines:
        raise SystemExit(f'{path}: no lines (tracks) found: nothing to make stages from')
    allpts = [p for _, pcs in lines for pc in pcs for p in pc]
    frame = Frame(sum(p[0] for p in allpts) / len(allpts), sum(p[1] for p in allpts) / len(allpts))
    controls, unmatched = match_controls([n for n, _ in lines], points)

    stages, used = [], set()
    for idx, (name, pieces) in enumerate(lines):
        ctl = controls[idx]
        start_xy = frame.xy(*ctl['start'][1:]) if 'start' in ctl else None
        line, gaps = stitch([[frame.xy(*p) for p in pc] for pc in pieces], start_xy)
        # driving direction: from the start control (else from whichever end the finish is not near)
        if start_xy is None and 'ff' in ctl:
            ff = frame.xy(*ctl['ff'][1:])
            if dist(line[0], ff) < dist(line[-1], ff):
                line.reverse()
        total = length(line)
        out_ctl = {}
        for role, (pname, lat, lon) in ctl.items():
            along, off = project(line, frame.xy(lat, lon))
            out_ctl[role] = {'name': pname, 'lat': round(lat, 7), 'lon': round(lon, 7),
                             'distM': round(along, 1), 'offLineM': round(off, 1)}
        (cx, cy), radius = enclosing_circle(line)
        clat, clon = frame.latlon(cx, cy)
        sid = slug(name)
        base, n = sid, 2
        while sid in used:
            sid, n = f'{base}-{n}', n + 1
        used.add(sid)
        stages.append({
            'id': sid, 'name': name,
            'lengthM': round(total, 1),
            'centre': {'lat': round(clat, 7), 'lon': round(clon, 7)}, 'radiusM': round(radius, 1),
            'pieces': len(pieces), 'gapsM': [round(g, 1) for g in gaps],
            'controls': out_ctl,
            'line': [[round(lat, 7), round(lon, 7)] for lat, lon in (frame.latlon(x, y) for x, y in line)],
        })
    others = [{'name': n, 'lat': round(lat, 7), 'lon': round(lon, 7)} for n, (lat, lon) in points]
    return {
        'format': FORMAT, 'id': event_id, 'name': event_name,
        'source': {'file': os.path.basename(path),
                   'note': "The organisers' map: for your own use, not for sharing."},
        'stages': stages, 'points': others,
    }, unmatched


def default_out_dir():
    base = os.environ.get('LOCALAPPDATA')
    if base:
        user = os.path.join(base, 'BeamNG', 'BeamNG.drive', 'current')
    else:
        user = os.path.expanduser('~/.local/share/BeamNG/BeamNG.drive/current')
    return os.path.join(user, 'earthRally', 'events')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('file', help='a .kml, .kmz or .gpx file')
    ap.add_argument('--id', help="the event's id (default: from the file name)")
    ap.add_argument('--name', help="the event's name (default: the file name)")
    ap.add_argument('--out', help=f'output folder (default: {default_out_dir()})')
    args = ap.parse_args()

    stem = os.path.splitext(os.path.basename(args.file))[0]
    event_id = args.id or re.sub(r'[^a-z0-9]+', '-', stem.lower()).strip('-')
    event, unmatched = build_event(args.file, event_id, args.name or stem)
    out_dir = args.out or default_out_dir()
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, event_id + '.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(event, f, indent=1, ensure_ascii=False)

    print(f"{event['name']}: {len(event['stages'])} stages -> {out}")
    for s in event['stages']:
        c = s['controls']
        roles = ' '.join(r for r in ('atc', 'start', 'ff', 'stop') if r in c) or 'no controls found'
        gaps = f", {s['pieces']} pieces (largest gap {max(s['gapsM']):.0f} m)" if s['gapsM'] else ''
        print(f"  {s['id']:<38} {s['lengthM'] / 1000:5.1f} km, fits a {s['radiusM'] / 1000:4.1f} km circle"
              f"{gaps}; controls: {roles}")
        for role in ('start', 'ff'):
            if role in c and c[role]['offLineM'] > 100:
                print(f"    note: its {role} control is {c[role]['offLineM']:.0f} m from the line")
        if s['gapsM'] and max(s['gapsM']) > GAP_WARN_M:
            print('    note: the pieces have gaps: the recce drive fills them in')
    if unmatched:
        print('  controls not matched to a stage (kept as plain points): ' + ', '.join(unmatched))
    return 0


if __name__ == '__main__':
    sys.exit(main())

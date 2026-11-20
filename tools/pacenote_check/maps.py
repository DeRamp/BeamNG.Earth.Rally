"""A picture of a stage and its calls (SVG): the road from above with each call written at its corner, the stretches
the rules flag in colour, and the height profile underneath with the calls marked along it. For looking a stage over
before anyone drives it."""
import html
from pathlib import Path

W, H_PLAN, H_PROF, PAD = 1600, 1100, 260, 40
FLAG = {'bend': '#e0245e', 'crest': '#f08c00', 'opening': '#7048e8', 'silence': '#868e96'}


def write(path, title, said, pts, rules, pro=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    st = said['startS'] or 0
    fi = said['finishS'] or pts[-1][3]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    sc = min((W - 2 * PAD) / max(maxx - minx, 1), (H_PLAN - 2 * PAD - 40) / max(maxy - miny, 1))

    def P(x, y):
        return PAD + (x - minx) * sc, 40 + PAD + (maxy - y) * sc

    def seg(a, b):
        out = []
        for p in pts:
            if a <= p[3] <= b:
                out.append('%.1f,%.1f' % P(p[0], p[1]))
        return ' '.join(out)

    def at(s):
        lo, hi = 0, len(pts) - 1
        while hi - lo > 1:
            m = (lo + hi) // 2
            if pts[m][3] <= s:
                lo = m
            else:
                hi = m
        return pts[lo]

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H_PLAN + H_PROF}" '
         f'font-family="Segoe UI, Arial" font-size="12">',
         '<rect width="100%" height="100%" fill="#fbfbf8"/>',
         f'<text x="{PAD}" y="28" font-size="20" font-weight="600">{html.escape(title)}</text>',
         f'<text x="{PAD + 700}" y="28" fill="#555">black: our calls'
         + (', blue: the pro\'s' if pro else '') +
         ' | red: bend not called | orange: corner hidden behind a crest | purple: silent opening</text>']
    o.append(f'<polyline points="{seg(-1e9, 1e9)}" fill="none" stroke="#c9c9c0" stroke-width="5"/>')
    o.append(f'<polyline points="{seg(st, fi)}" fill="none" stroke="#5c5c55" stroke-width="2"/>')
    op = rules.get('opening')
    if op and not op['ok'] and op['gapM']:
        o.append(f'<polyline points="{seg(st, st + op["gapM"])}" fill="none" stroke="{FLAG["opening"]}" '
                 f'stroke-width="9" opacity=".55"/>')
    for b in rules.get('bends', []):
        o.append(f'<polyline points="{seg(st + b["fromM"], st + b["toM"])}" fill="none" stroke="{FLAG["bend"]}" '
                 f'stroke-width="9" opacity=".6"/>')
    for c in rules.get('crests', []):
        if not c.get('flagged', True):
            continue
        o.append(f'<polyline points="{seg(st + c["atM"], st + c["cornerAtM"] + 20)}" fill="none" '
                 f'stroke="{FLAG["crest"]}" stroke-width="9" opacity=".7"/>')
    x0, y0 = P(*at(st)[:2])
    o.append(f'<circle cx="{x0:.1f}" cy="{y0:.1f}" r="7" fill="#2b8a3e"/><text x="{x0 + 9:.1f}" y="{y0 - 8:.1f}" '
             f'fill="#2b8a3e" font-weight="600">START</text>')

    def label(n, colour, dy):
        x, y = P(*at(n['s0'])[:2])
        o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3" fill="{colour}"/>')
        o.append(f'<text x="{x + 5:.1f}" y="{y + dy:.1f}" fill="{colour}" stroke="#fbfbf8" stroke-width="3" '
                 f'paint-order="stroke">{html.escape(n["text"][:48])}</text>')
    for n in pro or []:
        label(n, '#1c7ed6', 14)
    for n in said['notes']:
        label(n, '#111', -5)

    # the height profile
    top = H_PLAN + 10
    zs = [p[2] for p in pts if st - 50 <= p[3] <= fi + 50] or [0]
    zmin, zmax = min(zs), max(zs)
    zr = max(zmax - zmin, 10)
    sx = (W - 2 * PAD) / max(fi - st + 100, 1)

    def Q(s, z):
        return PAD + (s - st + 50) * sx, top + H_PROF - 30 - (z - zmin) / zr * (H_PROF - 60)
    prof = ' '.join('%.1f,%.1f' % Q(p[3], p[2]) for p in pts if st - 50 <= p[3] <= fi + 50)
    o.append(f'<line x1="{PAD}" y1="{top}" x2="{W - PAD}" y2="{top}" stroke="#ddd"/>')
    o.append(f'<polyline points="{prof}" fill="none" stroke="#5c5c55" stroke-width="1.5"/>')
    o.append(f'<text x="{PAD}" y="{top + 16}" fill="#555">height ({zmin:.0f}-{zmax:.0f} m), '
             f'{(fi - st) / 1000:.2f} km</text>')
    for c in rules.get('crests', []):
        if not c.get('flagged', True):
            continue
        x1, _ = Q(st + c['atM'], 0)
        x2, _ = Q(st + c['cornerAtM'], 0)
        o.append(f'<rect x="{x1:.1f}" y="{top + 20}" width="{max(x2 - x1, 3):.1f}" height="{H_PROF - 50}" '
                 f'fill="{FLAG["crest"]}" opacity=".25"/>')
    for n in said['notes']:
        x, y = Q(n['s0'], at(n['s0'])[2])
        colour = '#e8590c' if (n['p']['crest'] or n['p']['jump']) else '#111'
        o.append(f'<line x1="{x:.1f}" y1="{y:.1f}" x2="{x:.1f}" y2="{y - 14:.1f}" stroke="{colour}"/>')
    o.append('</svg>')
    path.write_text('\n'.join(o), encoding='utf-8')
    return path

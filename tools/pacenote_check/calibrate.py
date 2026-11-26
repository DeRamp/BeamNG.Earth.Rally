#!/usr/bin/env python3
"""Where the check's rules get their numbers: from the game's own stages, never from the mod's code.

    python tools/pacenote_check/calibrate.py [--game <BeamNG.drive folder>]

Reads the 15 rally stages with a pro co-driver's notes (their clean drivelines and the pro's words) and prints, for
each rule, the figure it is set from:
  - missed bends: the smallest turn (over 60 m up to the pro's longest corner) the pro calls 95 % of
    the time -> checks.BEND_MIN_DEG, checks.BEND_LENGTHS
  - hidden corner after a crest: with the eye at checks.EYE_M, the largest height of road that hides as many of the
    pro's lone crest and jump calls as 0.1 m does -> checks.TARGET_M
  - split bends: the pro's own rate of same-grade calls of one direction close together, by gap -> checks.SPLIT_GAP_M
Reads only. No Lua needed."""
import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check  # noqa: E402
import checks  # noqa: E402
import common  # noqa: E402


def stages(game):
    for name, nodes, nb, tr, start, finish, snb in common.pro_stages(game):
        if not nb.get('pacenotes'):
            continue
        line = common.game_spline(nodes, 2.0)
        s, pts = 0.0, []
        for k, p in enumerate(line):
            if k:
                s += math.dist((line[k - 1]['x'], line[k - 1]['y']), (p['x'], p['y']))
            pts.append((p['x'], p['y'], p['z'], s))
        pro = check.pro_notes(nb, tr, pts)
        if not pro:
            continue
        st = check.nearest_s(pts, start[0], start[1])[1] if start else 0
        fi = check.nearest_s(pts, finish[0], finish[1])[1] if finish else pts[-1][3]
        if fi <= st + 500:
            fi = pts[-1][3]
        yield name, pts, {'notes': pro, 'startS': st, 'finishS': fi}


def pct(xs, f):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * f))] if xs else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', default=common.DEFAULT_GAME)
    a = ap.parse_args()
    data = list(stages(a.game))
    km = sum((d['finishS'] - d['startS']) / 1000 for _, _, d in data)
    print(f'{len(data)} pro stages, {km:.0f} km')

    lens = [n['s1'] - n['s0'] for _, _, d in data for n in d['notes'] if n['p']['corners']]
    L95 = pct(lens, 0.95)
    print(f'pro corner length, longest: {max(lens):.0f} m')
    print(f'pro corner length, 50 / 90 / 95 %: {pct(lens, .5):.0f} / {pct(lens, .9):.0f} / {L95:.0f} m')
    top = int(max(lens) // 20) * 20      # (up to the pro's longest corner)
    checks.BEND_LENGTHS = range(60, top + 1, 20)
    cover = checks.BEND_COVER
    print('missed bends: turn -> share of such bends the pro leaves uncalled')
    pick = None
    for deg in range(15, 46, 1):
        checks.BEND_MIN_DEG = deg
        checks.BEND_COVER = 1.01          # every bend that turns that much
        allb = sum(len(checks.rule_bends(d, pts)) for _, pts, d in data)
        checks.BEND_COVER = cover
        miss = sum(len(checks.rule_bends(d, pts)) for _, pts, d in data)
        share = miss / max(allb, 1)
        print(f'  {deg:3d} deg  {miss:4d} of {allb:4d}  {share:.1%}')
        if pick is None and share <= 0.05:
            pick = deg
    print(f'-> BEND_MIN_DEG = {pick}, BEND_LENGTHS = range(60, {top + 1}, 20)')

    print(f'hidden road: eye {checks.EYE_M} m; share of the pro\'s lone crest / jump calls that hide this much road')
    lone = [(pts, n) for _, pts, d in data for n in d['notes']
            if (n['p']['crest'] or n['p']['jump']) and not n['p']['corners']]
    tpick, first = None, None
    for t10 in range(1, 13):
        checks.TARGET_M = t10 / 10
        hid = sum(1 for pts, n in lone if checks.hidden_after(pts, (n['s0'] + n['s1']) / 2))
        share = hid / max(len(lone), 1)
        print(f'  {checks.TARGET_M:.1f} m  {hid} of {len(lone)}  {share:.0%}')
        first = share if first is None else first
        if share >= first - 1.5 / max(len(lone), 1):   # (one call fewer at most)
            tpick = checks.TARGET_M
    print(f'-> TARGET_M = {tpick} (the most road hidden that still explains as many pro crest calls as 0.1 m, less one)')

    print('split bends: the pro\'s own rate (/km) by the gap allowed')
    for short in (20, 30, 40, 60, 1000):
        checks.SPLIT_SHORT_M = short
        row = []
        for g in (20, 30, 40, 50, 60, 80):
            checks.SPLIT_GAP_M = g
            n = sum(len(checks.rule_split(d, pts)) for _, pts, d in data)
            row.append(f'{g} m {n / km:.2f}')
        print(f'  both calls {short} m or shorter: ' + ', '.join(row))
    return 0


if __name__ == '__main__':
    sys.exit(main())

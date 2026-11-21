#!/usr/bin/env python3
"""Where pacenotes.GRADE_FIT_DIAMETERS comes from, and how well it holds on stages it was not fitted on.

    python tools/pacenote_check/check.py --only pro --no-history     # first: writes the pairs
    python tools/pacenote_check/ladder_fit.py [--folds 3]

Reads out/pacenote-check/last.json: for every corner of ours paired with a pro or game corner on the clean pro
stages, our fitted radius (pacenotes.fitRadius) and the truth's grade. Fits the five diameters that make our grade
the truth's most often (coordinate ascent from the game's own ladder), on all stages and then fold by fold: fit on
the other stages, score on the held-out ones. Prints the ladder and the in-sample and held-out same grade.
Reads only. No Lua needed."""
import argparse
import json
import sys
from pathlib import Path

LAST = Path(__file__).resolve().parents[2] / 'out' / 'pacenote-check' / 'last.json'
START = [35, 65, 116, 190, 260]          # the game's one to six
GRID = [(20, 45), (40, 80), (60, 130), (100, 200), (130, 300)]


def grade(d, T):
    return next((g for g, t in enumerate(T, 1) if d < t), len(T) + 1)


def stage_pairs(r):
    out = {}
    for name, v in r['pro'].items():
        P = []
        for src in ('versus', 'versusGame'):
            if v.get(src):
                P += [(x[0], x[2]) for x in v[src].get('pairs', []) if x[0] is not None and x[2] <= 6]
        out[name] = P
    return out


def same(P, T):
    return sum(grade(2 * r, T) == g for r, g in P) / max(len(P), 1)


def fit(P):
    T = START[:]
    for _ in range(6):
        for k, (lo, hi) in enumerate(GRID):
            best, bv = -1, T[k]
            for c in range(lo, hi, 3):
                T2 = T[:]
                T2[k] = c
                if T2 != sorted(T2):
                    continue
                sc = same(P, T2)
                if sc > best:
                    best, bv = sc, c
            T[k] = bv
    return T


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--folds', type=int, default=3)
    a = ap.parse_args()
    r = json.loads(LAST.read_text(encoding='utf-8'))
    by = stage_pairs(r)
    names = sorted(by)
    allP = [p for n in names for p in by[n]]
    T = fit(allP)
    print(f'{len(names)} stages, {len(allP)} corners')
    print(f'ladder, all stages: {T}  (in-sample same grade {same(allP, T):.3f}; game ladder {same(allP, START):.3f})')
    hits = n = 0
    for f in range(a.folds):
        test = [s for i, s in enumerate(names) if i % a.folds == f]
        train = [p for s in names if s not in test for p in by[s]]
        P = [p for s in test for p in by[s]]
        Tf = fit(train)
        h = sum(grade(2 * rr, Tf) == g for rr, g in P)
        hits, n = hits + h, n + len(P)
        print(f'  fold {f + 1}: fitted on {len(names) - len(test)} stages {Tf}, held out {len(test)}: '
              f'{h / max(len(P), 1):.3f} ({len(P)} corners)')
    print(f'held-out same grade: {hits / max(n, 1):.3f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
